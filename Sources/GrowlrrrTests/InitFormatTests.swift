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

    XCTAssertTrue(output.contains(#"notify = ["grrr", "send""#))
    XCTAssertTrue(output.contains(#""--title", "Codex""#))
    XCTAssertTrue(output.contains(#""--reactivate""#))
    XCTAssertTrue(output.contains(#""Codex needs your attention""#))
    XCTAssertTrue(output.contains("# Add this to ~/.codex/config.toml"))
    XCTAssertFalse(output.contains("hook notify"))
  }
}
