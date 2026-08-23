public enum InitFormat {
  public static func claudeCodeHooksJSON(appId: String? = nil) -> String {
    let appArgument = customAppArgument(appId)

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

  public static func codexConfigTOML(appId: String? = nil) -> String {
    let appArgument = customAppArgument(appId)

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
}
