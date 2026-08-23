import GrowlrrrCore
import XCTest

final class InitFormatTests: XCTestCase {
  func testCanonicalFormatNameRecognizesClaude() {
    XCTAssertEqual(InitFormat.canonicalName(for: "claude"), "claude")
  }

  func testCanonicalFormatNameTreatsClaudeCodeAsClaudeAlias() {
    XCTAssertEqual(InitFormat.canonicalName(for: "claude-code"), "claude")
    XCTAssertEqual(InitFormat.canonicalName(for: "CLAUDE-CODE"), "claude")
  }

  func testCanonicalFormatNameRecognizesCodexAndRejectsUnknownFormats() {
    XCTAssertEqual(InitFormat.canonicalName(for: "codex"), "codex")
    XCTAssertNil(InitFormat.canonicalName(for: "unknown"))
  }

  func testClaudeCodeFormatOutputsHooksJSON() {
    let output = InitFormat.claudeCodeHooksJSON()

    XCTAssertTrue(output.contains(#""Stop""#))
    XCTAssertTrue(output.contains(#""Notification""#))
    XCTAssertTrue(output.contains(#""UserPromptSubmit""#))
    XCTAssertTrue(output.contains(#""command": "grrr hook notify""#))
    XCTAssertTrue(output.contains(#""command": "grrr hook dismiss""#))
  }

  func testClaudeCodeFormatTargetsCustomApp() {
    let output = InitFormat.claudeCodeHooksJSON(appId: "ClaudeCode")

    XCTAssertTrue(output.contains(#""command": "grrr hook notify --appId ClaudeCode""#))
    XCTAssertTrue(output.contains(#""command": "grrr hook dismiss --appId ClaudeCode""#))
  }

  func testCodexFormatOutputsConfigToml() {
    let output = InitFormat.codexConfigTOML()

    XCTAssertTrue(output.contains("[[hooks.Stop]]"))
    XCTAssertTrue(output.contains("[[hooks.PermissionRequest]]"))
    XCTAssertTrue(output.contains("[[hooks.UserPromptSubmit]]"))
    XCTAssertTrue(output.contains("[tui]"))
    XCTAssertTrue(output.contains("notifications = false"))
    XCTAssertTrue(output.contains(#"command = "grrr hook notify --codex""#))
    XCTAssertTrue(output.contains(#"command = "grrr hook dismiss""#))
    XCTAssertTrue(output.contains("# Add this to ~/.codex/config.toml"))
    XCTAssertFalse(output.contains("notify ="))
    XCTAssertFalse(output.contains(#""send""#))
  }

  func testCodexFormatTargetsCustomApp() {
    let output = InitFormat.codexConfigTOML(appId: "Codex")

    XCTAssertTrue(output.contains(#"command = "grrr hook notify --codex --appId Codex""#))
    XCTAssertTrue(output.contains(#"command = "grrr hook dismiss --appId Codex""#))
  }
}
