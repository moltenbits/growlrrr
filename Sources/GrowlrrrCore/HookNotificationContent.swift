import Foundation

public struct HookNotificationContent: Equatable {
  /// A subtitle that says something about this event, such as which tool
  /// needs permission.
  let eventSubtitle: String?
  /// The line that only says the agent is waiting, shown as the subtitle
  /// when there is nothing better.
  let waitingSubtitle: String?
  public let message: String
  public let sessionId: String?

  /// The content of a notification whose message was given on the command
  /// line (`--message`), which has no subtitle of its own.
  public init(message: String, sessionId: String?) {
    self.init(eventSubtitle: nil, waitingSubtitle: nil, message: message, sessionId: sessionId)
  }

  init(eventSubtitle: String?, waitingSubtitle: String?, message: String, sessionId: String?) {
    self.eventSubtitle = eventSubtitle
    self.waitingSubtitle = waitingSubtitle
    self.message = message
    self.sessionId = sessionId
  }

  /// The subtitle when the application has no name for the conversation.
  public var subtitle: String? {
    subtitle(conversationName: nil)
  }

  /// The subtitle, given what the application the hook ran in calls the
  /// conversation (see `ApplicationAdapter.conversationName`). The name
  /// takes the place of the waiting line and fills an empty subtitle; it
  /// never replaces what the event says about itself.
  public func subtitle(conversationName: String?) -> String? {
    eventSubtitle ?? conversationName ?? waitingSubtitle
  }
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
          eventSubtitle: nil,
          waitingSubtitle: waiting,
          message: truncated(lastAssistantMessage),
          sessionId: sessionId
        )
      }
      return HookNotificationContent(message: waiting, sessionId: sessionId)

    case "PermissionRequest":
      let toolInput = json["tool_input"] as? [String: Any]
      let message =
        string(toolInput?["description"])
        ?? string(toolInput?["command"])
        ?? jsonSummary(toolInput)
        ?? "\(agent.name) wants permission to continue"

      return HookNotificationContent(
        eventSubtitle: permissionSubtitle(agent: agent, toolName: string(json["tool_name"])),
        waitingSubtitle: nil,
        message: truncated(message),
        sessionId: sessionId
      )

    default:
      // Events that carry their own text, such as Claude Code's
      // Notification: {"title": ..., "message": ...}.
      return HookNotificationContent(
        eventSubtitle: string(json["title"]),
        waitingSubtitle: nil,
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
