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
  /// A literal single quote becomes `'\''`. Backslashes and double quotes are
  /// escaped as well so the line stays valid inside a JSON or TOML string.
  private static func gateArgument(_ gate: String?) -> String {
    guard let gate else { return "" }
    let shellQuoted = "'" + gate.replacingOccurrences(of: "'", with: "'\\''") + "'"
    let stringSafe =
      shellQuoted
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return " --gate \(stringSafe)"
  }
}
