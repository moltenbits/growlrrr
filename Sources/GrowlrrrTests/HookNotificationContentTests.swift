import GrowlrrrCore
import XCTest

final class HookNotificationContentTests: XCTestCase {
  func testClaudeCodeStopPreservesExistingReadyMessage() {
    let content = HookNotificationContentResolver.claudeCode(from: [
      "hook_event_name": "Stop",
      "session_id": "claude-session",
      "last_assistant_message": "Done",
    ])

    XCTAssertEqual(content.subtitle, nil)
    XCTAssertEqual(content.message, "Claude is ready")
    XCTAssertEqual(content.sessionId, "claude-session")
  }

  func testCodexStopUsesLastAssistantMessage() {
    let content = HookNotificationContentResolver.codex(from: [
      "hook_event_name": "Stop",
      "session_id": "codex-session",
      "last_assistant_message": "Implemented the change and tests pass.",
    ])

    XCTAssertEqual(content.subtitle, "Codex is waiting for your input")
    XCTAssertEqual(content.message, "Implemented the change and tests pass.")
    XCTAssertEqual(content.sessionId, "codex-session")
  }

  func testCodexStopFallsBackWhenNoAssistantMessageExists() {
    let content = HookNotificationContentResolver.codex(from: [
      "hook_event_name": "Stop",
      "session_id": "codex-session",
    ])

    XCTAssertEqual(content.subtitle, nil)
    XCTAssertEqual(content.message, "Codex is waiting for your input")
    XCTAssertEqual(content.sessionId, "codex-session")
  }

  func testCodexPermissionRequestUsesDescription() {
    let content = HookNotificationContentResolver.codex(from: [
      "hook_event_name": "PermissionRequest",
      "session_id": "codex-session",
      "tool_name": "Bash",
      "tool_input": [
        "command": "git commit -m test",
        "description": "Codex wants to create a git commit.",
      ],
    ])

    XCTAssertEqual(content.subtitle, "Codex needs permission: Bash")
    XCTAssertEqual(content.message, "Codex wants to create a git commit.")
    XCTAssertEqual(content.sessionId, "codex-session")
  }

  func testCodexPermissionRequestFallsBackToCommand() {
    let content = HookNotificationContentResolver.codex(from: [
      "hook_event_name": "PermissionRequest",
      "session_id": "codex-session",
      "tool_name": "Bash",
      "tool_input": [
        "command": "git status --short",
      ],
    ])

    XCTAssertEqual(content.subtitle, "Codex needs permission: Bash")
    XCTAssertEqual(content.message, "git status --short")
    XCTAssertEqual(content.sessionId, "codex-session")
  }
}
