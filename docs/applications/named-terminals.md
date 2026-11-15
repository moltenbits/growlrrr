# Warp, Alacritty, and kitty

Clicking a notification sent from Warp, Alacritty, or kitty brings that app forward. It does not select a window or tab.

## How it works

growlrrr recognises these terminals by `TERM_PROGRAM`:

| `TERM_PROGRAM` | App activated |
|----------------|---------------|
| `WarpTerminal` | Warp |
| `Alacritty` | Alacritty |
| `kitty` | kitty |

The click runs `osascript -e 'tell application "<App>" to activate'`. Because it goes by `TERM_PROGRAM` rather than by which app started the command, it also works for a shell that has been detached from its terminal.

## Permissions

These terminals only use simple app activation and do not trigger the Automation permission prompt.

## Implementation

`NamedTerminalAdapter` in `Sources/GrowlrrrCore/Adapters/`.
