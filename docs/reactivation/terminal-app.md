# Terminal.app

Clicking a notification sent from Terminal.app returns to the window and tab it was sent from.

## How it works

growlrrr recognises Terminal.app by `TERM_PROGRAM=Apple_Terminal`. While the notification is being sent, it asks Terminal.app for the id of the front window and the index of its selected tab. The click runs an AppleScript that selects that tab, brings that window to the front, and activates Terminal.app.

If the window and tab cannot be read, the click brings Terminal.app forward.

## Limits

The window and tab are the ones in front when the notification is sent, not the ones the command was started in. If you switch to another Terminal.app window or tab while the command runs, the click returns to that one.

## Permissions

macOS asks once for permission for growlrrr to control Terminal.app (System Settings > Privacy & Security > Automation). Without it, the click can only bring Terminal.app forward.

## Implementation

`TerminalAppReactivation` in `Sources/GrowlrrrCore/Reactivation/`.
