import Foundation

public struct HookNotificationContent: Equatable {
  public let subtitle: String?
  public let message: String
  public let sessionId: String?
}

/// The coding agent whose hook is sending the notification. It only supplies
/// the name used in the text; the format is the same for every agent.
public enum HookAgent {
  case claudeCode
  case codex

  var name: String {
    switch self {
    case .claudeCode: return "Claude"
    case .codex: return "Codex"
    }
  }
}

public enum HookNotificationContentResolver {
  /// Turns the JSON an agent pipes to a hook into notification text.
  public static func content(from json: [String: Any], agent: HookAgent) -> HookNotificationContent {
    let sessionId = string(json["session_id"])
    let waiting = "\(agent.name) is waiting for your input"

    switch string(json["hook_event_name"]) {
    case "Stop":
      // The turn ended: show what the agent last said.
      if let lastAssistantMessage = string(json["last_assistant_message"]) {
        return HookNotificationContent(
          subtitle: waiting,
          message: truncated(lastAssistantMessage),
          sessionId: sessionId
        )
      }
      return HookNotificationContent(subtitle: nil, message: waiting, sessionId: sessionId)

    case "PermissionRequest":
      let toolInput = json["tool_input"] as? [String: Any]
      let message =
        string(toolInput?["description"])
        ?? string(toolInput?["command"])
        ?? jsonSummary(toolInput)
        ?? "\(agent.name) wants permission to continue"

      return HookNotificationContent(
        subtitle: permissionSubtitle(agent: agent, toolName: string(json["tool_name"])),
        message: truncated(message),
        sessionId: sessionId
      )

    default:
      // Events that carry their own text, such as Claude Code's
      // Notification: {"title": ..., "message": ...}.
      return HookNotificationContent(
        subtitle: string(json["title"]),
        message: string(json["message"]).map { truncated($0) } ?? waiting,
        sessionId: sessionId
      )
    }
  }

  private static func permissionSubtitle(agent: HookAgent, toolName: String?) -> String {
    guard let toolName else {
      return "\(agent.name) needs permission"
    }
    return "\(agent.name) needs permission: \(toolName)"
  }

  private static func string(_ value: Any?) -> String? {
    guard let value = value as? String else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func jsonSummary(_ value: Any?) -> String? {
    guard let value else { return nil }
    guard JSONSerialization.isValidJSONObject(value),
      let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
      let encoded = String(data: data, encoding: .utf8)
    else {
      return nil
    }
    return encoded
  }

  private static func truncated(_ value: String, maxLength: Int = 240) -> String {
    let singleLine = value
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "\t", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    guard singleLine.count > maxLength else {
      return singleLine
    }

    let end = singleLine.index(singleLine.startIndex, offsetBy: maxLength - 3)
    return String(singleLine[..<end]) + "..."
  }
}
