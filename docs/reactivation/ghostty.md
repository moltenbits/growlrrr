# Ghostty

Clicking a notification sent from Ghostty returns to the terminal it was sent from.

## How it works

growlrrr recognises Ghostty by `TERM_PROGRAM=ghostty`. While the notification is being sent, it asks Ghostty for the id of the focused terminal in the selected tab of the front window. The click runs an AppleScript that activates Ghostty and focuses the terminal with that id.

If the terminal's id cannot be read, the click brings Ghostty forward.

## Limits

The terminal is the one focused when the notification is sent. If you switch Ghostty tabs between starting a command and the notification firing, the wrong tab may be targeted. Ghostty does not yet provide a session id environment variable (see [ghostty-org/ghostty#10603](https://github.com/ghostty-org/ghostty/discussions/10603)).

## Permissions

macOS asks once for permission for growlrrr to control Ghostty (System Settings > Privacy & Security > Automation). Without it, the click can only bring Ghostty forward.

## Implementation

`GhosttyReactivation` in `Sources/GrowlrrrCore/Reactivation/`.
