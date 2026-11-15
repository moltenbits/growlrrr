import GrowlrrrCore
import XCTest

/// Claude Code and Codex hooks produce the same notification text; only the
/// agent's name differs.
final class HookNotificationContentTests: XCTestCase {
  private let agents: [(agent: HookAgent, name: String)] = [(.claudeCode, "Claude"), (.codex, "Codex")]

  // MARK: - Stop

  func testStopShowsTheLastAssistantMessageUnderAWaitingSubtitle() {
    for (agent, name) in agents {
      let content = HookNotificationContentResolver.content(
        from: [
          "hook_event_name": "Stop",
          "session_id": "session-1",
          "last_assistant_message": "Implemented the change and tests pass.",
        ],
        agent: agent)

      XCTAssertEqual(content.subtitle, "\(name) is waiting for your input")
      XCTAssertEqual(content.message, "Implemented the change and tests pass.")
      XCTAssertEqual(content.sessionId, "session-1")
    }
  }

  func testStopWithoutAnAssistantMessageShowsOnlyTheWaitingLine() {
    for (agent, name) in agents {
      for json in [
        ["hook_event_name": "Stop", "session_id": "session-1"],
        ["hook_event_name": "Stop", "session_id": "session-1", "last_assistant_message": "  \n "],
      ] {
        let content = HookNotificationContentResolver.content(from: json, agent: agent)

        XCTAssertEqual(content.subtitle, nil)
        XCTAssertEqual(content.message, "\(name) is waiting for your input")
        XCTAssertEqual(content.sessionId, "session-1")
      }
    }
  }

  func testStopPutsALongMessageOnOneLineAndCutsItAt240Characters() {
    let longMessage = "First line.\nSecond line.\t" + String(repeating: "x", count: 300)
    for (agent, _) in agents {
      let content = HookNotificationContentResolver.content(
        from: ["hook_event_name": "Stop", "last_assistant_message": longMessage], agent: agent)

      XCTAssertEqual(content.message.count, 240)
      XCTAssertTrue(content.message.hasPrefix("First line. Second line. xxx"))
      XCTAssertTrue(content.message.hasSuffix("..."))
    }
  }

  // MARK: - PermissionRequest

  func testPermissionRequestShowsTheReasonUnderTheToolName() {
    for (agent, name) in agents {
      let content = HookNotificationContentResolver.content(
        from: [
          "hook_event_name": "PermissionRequest",
          "session_id": "session-1",
          "tool_name": "Bash",
          "tool_input": [
            "command": "git commit -m test",
            "description": "Create a git commit.",
          ],
        ],
        agent: agent)

      XCTAssertEqual(content.subtitle, "\(name) needs permission: Bash")
      XCTAssertEqual(content.message, "Create a git commit.")
      XCTAssertEqual(content.sessionId, "session-1")
    }
  }

  func testPermissionRequestFallsBackToTheCommand() {
    for (agent, name) in agents {
      let content = HookNotificationContentResolver.content(
        from: [
          "hook_event_name": "PermissionRequest",
          "tool_name": "Bash",
          "tool_input": ["command": "git status --short"],
        ],
        agent: agent)

      XCTAssertEqual(content.subtitle, "\(name) needs permission: Bash")
      XCTAssertEqual(content.message, "git status --short")
    }
  }

  func testPermissionRequestWithoutDetailsStillSaysWhoIsAsking() {
    for (agent, name) in agents {
      let content = HookNotificationContentResolver.content(
        from: ["hook_event_name": "PermissionRequest"], agent: agent)

      XCTAssertEqual(content.subtitle, "\(name) needs permission")
      XCTAssertEqual(content.message, "\(name) wants permission to continue")
    }
  }

  // MARK: - Other events

  func testAnEventThatCarriesItsOwnTextShowsThatText() {
    // Claude Code's Notification event: {"title": ..., "message": ...}.
    for (agent, _) in agents {
      let content = HookNotificationContentResolver.content(
        from: [
          "hook_event_name": "Notification",
          "session_id": "session-1",
          "title": "Permission needed",
          "message": "Claude needs your permission to use Bash",
        ],
        agent: agent)

      XCTAssertEqual(content.subtitle, "Permission needed")
      XCTAssertEqual(content.message, "Claude needs your permission to use Bash")
      XCTAssertEqual(content.sessionId, "session-1")
    }
  }

  func testAnEventWithOnlyAMessageHasNoSubtitle() {
    for (agent, _) in agents {
      let content = HookNotificationContentResolver.content(
        from: ["hook_event_name": "Notification", "message": "Claude is waiting for your input"],
        agent: agent)

      XCTAssertEqual(content.subtitle, nil)
      XCTAssertEqual(content.message, "Claude is waiting for your input")
    }
  }

  func testAnEventWithNoTextFallsBackToTheWaitingLine() {
    for (agent, name) in agents {
      for json in [["hook_event_name": "Notification"], [:]] {
        let content = HookNotificationContentResolver.content(from: json, agent: agent)

        XCTAssertEqual(content.subtitle, nil)
        XCTAssertEqual(content.message, "\(name) is waiting for your input")
        XCTAssertEqual(content.sessionId, nil)
      }
    }
  }

  // MARK: - Conversation name

  func testAConversationNameTakesThePlaceOfTheWaitingSubtitle() {
    for (agent, _) in agents {
      let content = HookNotificationContentResolver.content(
        from: [
          "hook_event_name": "Stop",
          "last_assistant_message": "Implemented the change and tests pass.",
        ],
        agent: agent)

      XCTAssertEqual(content.subtitle(conversationName: "Fix the login page"), "Fix the login page")
      XCTAssertEqual(content.message, "Implemented the change and tests pass.")
    }
  }

  func testWithoutAConversationNameTheSubtitleIsTheDefault() {
    for (agent, name) in agents {
      let content = HookNotificationContentResolver.content(
        from: ["hook_event_name": "Stop", "last_assistant_message": "Done."], agent: agent)

      XCTAssertEqual(content.subtitle(conversationName: nil), "\(name) is waiting for your input")
      XCTAssertEqual(content.subtitle(conversationName: nil), content.subtitle)
    }
  }

  func testAConversationNameFillsAnEmptySubtitle() {
    for (agent, name) in agents {
      // A turn that ended without a message: the waiting line is the body.
      let stop = HookNotificationContentResolver.content(from: ["hook_event_name": "Stop"], agent: agent)
      XCTAssertEqual(stop.subtitle(conversationName: "Fix the login page"), "Fix the login page")
      XCTAssertEqual(stop.message, "\(name) is waiting for your input")

      let notification = HookNotificationContentResolver.content(
        from: ["hook_event_name": "Notification", "message": "Claude is waiting for your input"],
        agent: agent)
      XCTAssertEqual(notification.subtitle(conversationName: "Fix the login page"), "Fix the login page")
    }
  }

  func testAConversationNameDoesNotReplaceWhatTheEventSaysAboutItself() {
    for (agent, name) in agents {
      let permission = HookNotificationContentResolver.content(
        from: [
          "hook_event_name": "PermissionRequest", "tool_name": "Bash",
          "tool_input": ["command": "git push"],
        ],
        agent: agent)
      XCTAssertEqual(
        permission.subtitle(conversationName: "Fix the login page"), "\(name) needs permission: Bash")

      let titled = HookNotificationContentResolver.content(
        from: ["hook_event_name": "Notification", "title": "Heads up", "message": "Something happened"],
        agent: agent)
      XCTAssertEqual(titled.subtitle(conversationName: "Fix the login page"), "Heads up")
    }
  }

  func testAMessageGivenOnTheCommandLineHasOnlyTheConversationNameAsSubtitle() {
    let content = HookNotificationContent(message: "Build finished", sessionId: "session-1")

    XCTAssertEqual(content.message, "Build finished")
    XCTAssertEqual(content.sessionId, "session-1")
    XCTAssertNil(content.subtitle)
    XCTAssertEqual(content.subtitle(conversationName: "Fix the login page"), "Fix the login page")
  }
}
