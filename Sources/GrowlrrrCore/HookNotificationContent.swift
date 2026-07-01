import Foundation

public struct HookNotificationContent: Equatable {
  public let subtitle: String?
  public let message: String
  public let sessionId: String?
}

public enum HookNotificationContentResolver {
  public static func claudeCode(from json: [String: Any]) -> HookNotificationContent {
    let sessionId = string(json["session_id"])
    let eventName = string(json["hook_event_name"])

    if eventName == "Stop" {
      return HookNotificationContent(
        subtitle: nil,
        message: "Claude is ready",
        sessionId: sessionId
      )
    }

    return HookNotificationContent(
      subtitle: string(json["title"]),
      message: string(json["message"]) ?? "Notification",
      sessionId: sessionId
    )
  }

  public static func codex(from json: [String: Any]) -> HookNotificationContent {
    let sessionId = string(json["session_id"])
    let eventName = string(json["hook_event_name"])

    switch eventName {
    case "Stop":
      if let lastAssistantMessage = string(json["last_assistant_message"]) {
        return HookNotificationContent(
          subtitle: "Codex is waiting for your input",
          message: truncated(lastAssistantMessage),
          sessionId: sessionId
        )
      }
      return HookNotificationContent(
        subtitle: nil,
        message: "Codex is waiting for your input",
        sessionId: sessionId
      )

    case "PermissionRequest":
      let toolName = string(json["tool_name"])
      let toolInput = json["tool_input"] as? [String: Any]
      let message =
        string(toolInput?["description"])
        ?? string(toolInput?["command"])
        ?? jsonSummary(toolInput)
        ?? "Codex wants permission to continue"

      return HookNotificationContent(
        subtitle: permissionSubtitle(toolName: toolName),
        message: truncated(message),
        sessionId: sessionId
      )

    default:
      return HookNotificationContent(
        subtitle: eventName.map { "Codex \($0)" },
        message: string(json["message"]) ?? "Codex is waiting for your input",
        sessionId: sessionId
      )
    }
  }

  private static func permissionSubtitle(toolName: String?) -> String {
    guard let toolName, !toolName.isEmpty else {
      return "Codex needs permission"
    }
    return "Codex needs permission: \(toolName)"
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
