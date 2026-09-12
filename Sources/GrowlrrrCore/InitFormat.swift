public enum InitFormat {
  public static func canonicalName(for value: String) -> String? {
    switch value.lowercased() {
    case "claude", "claude-code":
      return "claude"
    case "codex":
      return "codex"
    default:
      return nil
    }
  }

  public static func claudeCodeHooksJSON(appId: String? = nil, gate: String? = nil) -> String {
    let appArgument = customAppArgument(appId) + gateArgument(gate)

    return """
      {
        "hooks": {
          "Stop": [
            {
              "hooks": [
                {
                  "type": "command",
                  "command": "grrr hook notify\(appArgument)"
                }
              ]
            }
          ],
          "Notification": [
            {
              "hooks": [
                {
                  "type": "command",
                  "command": "grrr hook notify\(appArgument)"
                }
              ]
            }
          ],
          "UserPromptSubmit": [
            {
              "hooks": [
                {
                  "type": "command",
                  "command": "grrr hook dismiss\(appArgument)"
                }
              ]
            }
          ]
        }
      }
      """
  }

  public static func codexConfigTOML(appId: String? = nil, gate: String? = nil) -> String {
    let appArgument = customAppArgument(appId) + gateArgument(gate)

    return """
      # Add this to ~/.codex/config.toml
      # Codex project .codex/config.toml files only load after you trust the project.

      [tui]
      notifications = false

      [[hooks.Stop]]
      [[hooks.Stop.hooks]]
      type = "command"
      command = "grrr hook notify --codex\(appArgument)"
      timeout = 30

      [[hooks.PermissionRequest]]
      [[hooks.PermissionRequest.hooks]]
      type = "command"
      command = "grrr hook notify --codex\(appArgument)"
      timeout = 30
      statusMessage = "Sending notification"

      [[hooks.UserPromptSubmit]]
      [[hooks.UserPromptSubmit.hooks]]
      type = "command"
      command = "grrr hook dismiss\(appArgument)"
      timeout = 30
      """
  }

  private static func customAppArgument(_ appId: String?) -> String {
    guard let appId else { return "" }
    return " --appId \(appId)"
  }

  /// `--gate '<command>'`, single-quoted for the shell the host runs hooks in.
  /// A literal single quote becomes `'\''`. The result is then encoded for the
  /// double-quoted string it is embedded in, so the config stays valid.
  private static func gateArgument(_ gate: String?) -> String {
    guard let gate else { return "" }
    let shellQuoted = "'" + gate.replacingOccurrences(of: "'", with: "'\\''") + "'"
    return " --gate \(escapedForQuotedString(shellQuoted))"
  }

  /// Escapes `text` so it can sit inside a JSON string or a TOML basic string.
  /// Both formats share these escapes: `\\`, `\"`, `\b`, `\t`, `\n`, `\f`,
  /// `\r`, and `\uXXXX` for the remaining control characters.
  private static func escapedForQuotedString(_ text: String) -> String {
    var out = ""
    for scalar in text.unicodeScalars {
      switch scalar {
      case "\\": out += "\\\\"
      case "\"": out += "\\\""
      case "\u{08}": out += "\\b"
      case "\t": out += "\\t"
      case "\n": out += "\\n"
      case "\u{0C}": out += "\\f"
      case "\r": out += "\\r"
      case _ where scalar.value < 0x20 || scalar.value == 0x7F:
        out += String(format: "\\u%04X", scalar.value)
      default: out.unicodeScalars.append(scalar)
      }
    }
    return out
  }
}
