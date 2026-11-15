# iTerm2

Clicking a notification sent from iTerm2 returns to the session it was sent from: the window, the tab, and the pane.

## How it works

growlrrr recognises iTerm2 by `TERM_PROGRAM=iTerm.app`, and then uses the first of these that is available:

1. **The session id.** iTerm2 sets `ITERM_SESSION_ID` in every session. growlrrr stores `open 'iterm2:reveal?sessionid=<id>'` as the click action. iTerm2 handles that URL itself, so it finds the session even when its window is minimized or behind other windows.
2. **The terminal device.** Without a usable session id, and when growlrrr's input is attached to a terminal, the click runs an AppleScript that looks for the session with that tty.
3. **The current session.** Failing that, growlrrr asks iTerm2 which session is current while the notification is being sent, and the click looks for that session. If you have moved to another session by then, that one is targeted.
4. **The app.** If none of those work, the click brings iTerm2 forward.

## Permissions

The session id route needs none. The other routes use AppleScript, so macOS asks once for permission for growlrrr to control iTerm2 (System Settings > Privacy & Security > Automation).

## Implementation

`ITermReactivation` and `ITermSession` in `Sources/GrowlrrrCore/Reactivation/`.
