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
      # Codex project .codex/config.toml files cannot set external notifiers.
      notify = ["grrr", "hook", "notify", "--message", "Codex is ready", "--replace"]
      """
  }
}
