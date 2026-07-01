import GrowlrrrCore
import XCTest

final class InitFormatTests: XCTestCase {
  func testClaudeCodeFormatOutputsHooksJSON() {
    let output = InitFormat.claudeCodeHooksJSON()

    XCTAssertTrue(output.contains(#""Stop""#))
    XCTAssertTrue(output.contains(#""Notification""#))
    XCTAssertTrue(output.contains(#""UserPromptSubmit""#))
    XCTAssertTrue(output.contains(#""command": "grrr hook notify""#))
    XCTAssertTrue(output.contains(#""command": "grrr hook dismiss""#))
  }

  func testCodexFormatOutputsConfigToml() {
    let output = InitFormat.codexConfigTOML()

    XCTAssertTrue(output.contains("[[hooks.Stop]]"))
    XCTAssertTrue(output.contains("[[hooks.PermissionRequest]]"))
    XCTAssertTrue(output.contains("[[hooks.UserPromptSubmit]]"))
    XCTAssertTrue(output.contains(#"command = "grrr hook notify --codex""#))
    XCTAssertTrue(output.contains(#"command = "grrr hook dismiss""#))
    XCTAssertTrue(output.contains("# Add this to ~/.codex/config.toml"))
    XCTAssertFalse(output.contains("notify ="))
    XCTAssertFalse(output.contains(#""send""#))
  }
}
