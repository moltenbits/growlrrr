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

// MARK: - Gate option

final class InitFormatGateTests: XCTestCase {
  func testClaudeCodeFormatWithoutGateIsUnchanged() {
    XCTAssertEqual(InitFormat.claudeCodeHooksJSON(gate: nil), InitFormat.claudeCodeHooksJSON())
    XCTAssertFalse(InitFormat.claudeCodeHooksJSON().contains("--gate"))
    XCTAssertFalse(InitFormat.codexConfigTOML().contains("--gate"))
  }

  func testClaudeCodeFormatPutsGateOnEveryHookLine() {
    let output = InitFormat.claudeCodeHooksJSON(appId: "Sideband", gate: "sideband hook notify")

    let notifyLines = output.components(separatedBy: "\n").filter {
      $0.contains("grrr hook notify")
    }
    let dismissLines = output.components(separatedBy: "\n").filter {
      $0.contains("grrr hook dismiss")
    }
    XCTAssertEqual(notifyLines.count, 2)
    XCTAssertEqual(dismissLines.count, 1)
    for line in notifyLines {
      XCTAssertTrue(
        line.contains(
          #""command": "grrr hook notify --appId Sideband --gate 'sideband hook notify'""#), line)
    }
    for line in dismissLines {
      XCTAssertTrue(
        line.contains(
          #""command": "grrr hook dismiss --appId Sideband --gate 'sideband hook notify'""#), line)
    }
  }

  func testClaudeCodeFormatGateWithoutAppId() {
    let output = InitFormat.claudeCodeHooksJSON(gate: "my-gate")
    XCTAssertTrue(output.contains(#""command": "grrr hook notify --gate 'my-gate'""#))
    XCTAssertTrue(output.contains(#""command": "grrr hook dismiss --gate 'my-gate'""#))
  }

  func testCodexFormatPutsGateOnEveryHookLine() {
    let output = InitFormat.codexConfigTOML(appId: "Sideband", gate: "sideband hook notify")

    let notifyLines = output.components(separatedBy: "\n").filter {
      $0.contains("grrr hook notify")
    }
    let dismissLines = output.components(separatedBy: "\n").filter {
      $0.contains("grrr hook dismiss")
    }
    XCTAssertEqual(notifyLines.count, 2)
    XCTAssertEqual(dismissLines.count, 1)
    for line in notifyLines {
      XCTAssertEqual(
        line,
        #"command = "grrr hook notify --codex --appId Sideband --gate 'sideband hook notify'""#)
    }
    for line in dismissLines {
      XCTAssertEqual(
        line, #"command = "grrr hook dismiss --appId Sideband --gate 'sideband hook notify'""#)
    }
  }

  func testGateContainingSingleQuoteIsEscapedForTheShell() throws {
    // The shell must see `'echo it'\''s'`. Inside a JSON or TOML basic string
    // that backslash is itself escaped, so the file text carries `\\`.
    let claude = InitFormat.claudeCodeHooksJSON(gate: "echo it's")
    XCTAssertTrue(claude.contains(#"--gate 'echo it'\\''s'"#), claude)

    let json = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(claude.utf8)) as? [String: Any])
    let hooks = try XCTUnwrap(json["hooks"] as? [String: Any])
    let stop = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
    let entry = try XCTUnwrap((stop.first?["hooks"] as? [[String: Any]])?.first)
    XCTAssertEqual(entry["command"] as? String, #"grrr hook notify --gate 'echo it'\''s'"#)

    let codex = InitFormat.codexConfigTOML(gate: "echo it's")
    XCTAssertTrue(codex.contains(#"--gate 'echo it'\\''s'"#), codex)
  }

  func testGateWithControlCharactersProducesValidJSON() throws {
    let gate = "true\nexit 0\ttab \"quoted\" back\\slash"
    let claude = InitFormat.claudeCodeHooksJSON(gate: gate)

    let json = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(claude.utf8)) as? [String: Any])
    let hooks = try XCTUnwrap(json["hooks"] as? [String: Any])
    let stop = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
    let entry = try XCTUnwrap((stop.first?["hooks"] as? [[String: Any]])?.first)
    XCTAssertEqual(entry["command"] as? String, "grrr hook notify --gate '\(gate)'")
  }

  func testGateWithControlCharactersIsEscapedForTOML() {
    let codex = InitFormat.codexConfigTOML(gate: "a\nb\tc\rd\u{7f}e")
    let line = codex.components(separatedBy: "\n").first { $0.contains("grrr hook dismiss") }
    XCTAssertEqual(line, #"command = "grrr hook dismiss --gate 'a\nb\tc\rd\u007Fe'""#)
  }

  func testGateOnlyChangesHookCommandLines() {
    let plain = InitFormat.codexConfigTOML(appId: "Sideband")
    let gated = InitFormat.codexConfigTOML(appId: "Sideband", gate: "g")
    let strip: (String) -> [String] = { text in
      text.components(separatedBy: "\n").filter { !$0.contains("grrr hook") }
    }
    XCTAssertEqual(strip(plain), strip(gated))
  }
}
