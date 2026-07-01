public enum InitFormat {
  public static func claudeCodeHooksJSON() -> String {
    return """
      {
        "hooks": {
          "Stop": [
            {
              "hooks": [
                {
                  "type": "command",
                  "command": "grrr hook notify"
                }
              ]
            }
          ],
          "Notification": [
            {
              "hooks": [
                {
                  "type": "command",
                  "command": "grrr hook notify"
                }
              ]
            }
          ],
          "UserPromptSubmit": [
            {
              "hooks": [
                {
                  "type": "command",
                  "command": "grrr hook dismiss"
                }
              ]
            }
          ]
        }
      }
      """
  }

  public static func codexConfigTOML() -> String {
    return """
      # Add this to ~/.codex/config.toml
      # Codex project .codex/config.toml files only load after you trust the project.

      [tui]
      notifications = false

      [[hooks.Stop]]
      [[hooks.Stop.hooks]]
      type = "command"
      command = "grrr hook notify --codex"
      timeout = 30

      [[hooks.PermissionRequest]]
      [[hooks.PermissionRequest.hooks]]
      type = "command"
      command = "grrr hook notify --codex"
      timeout = 30
      statusMessage = "Sending notification"

      [[hooks.UserPromptSubmit]]
      [[hooks.UserPromptSubmit.hooks]]
      type = "command"
      command = "grrr hook dismiss"
      timeout = 30
      """
  }
}
