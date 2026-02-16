# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
make build              # Debug build (executable only)
make release            # Release build (executable only)
make bundle             # Debug app bundle (required for notifications to work)
make bundle-release     # Release app bundle
make test               # Run tests
make install            # Build release bundle, install to /Applications, create symlinks
make run                # Build debug bundle and send a test notification
make format             # Format code (requires swift-format)
make lint               # Lint code (requires swift-format)
```

All swift commands use `--disable-sandbox`. The app bundle is built via `scripts/bundle.sh` which compiles, creates the `.app` structure, generates shell completions, and code-signs.

## Architecture

**growlrrr** is a macOS CLI tool that sends native notifications via the UserNotifications framework. It requires a proper `.app` bundle — bare executables cannot send notifications on macOS.

### Targets (Package.swift — Swift 5.9, macOS 13.0+)

- **`growlrrr`** (executable) — CLI entry point, depends on ArgumentParser and GrowlrrrCore
- **`GrowlrrrCore`** (library) — Shared models, custom app bundle management
- **`GrowlrrrTests`** — XCTest suite testing models and bundle logic

### Key Source Files

| File | Purpose |
|------|---------|
| `Sources/growlrrr/Growlrrr.swift` | Main entry point (`GrowlrrrMain`) and all subcommands (`Send`, `List`, `Clear`, `Authorize`, `Apps`, `Init`) |
| `Sources/growlrrr/NotificationService.swift` | Async actor wrapping `UNUserNotificationCenter` — sending, waiting, listing, clearing |
| `Sources/GrowlrrrCore/CustomAppBundle.swift` | Creates/manages lightweight app bundles with custom icons in `~/.growlrrr/apps/` |
| `Sources/GrowlrrrCore/Models.swift` | `NotificationConfig`, `SoundOption`, `NotificationInfo`, `GrowlrrrError` |

### Dual Launch Context

The app handles two launch modes in `GrowlrrrMain`:
1. **CLI invocation** — Parses arguments via ArgumentParser, runs the requested subcommand
2. **Notification click** — macOS relaunches the app; `NotificationLaunchHandler` (NSApplication delegate) executes embedded `execute`/`open` commands from the notification's userInfo

### Terminal Reactivation (`--reactivate`)

Captures terminal identity at send time and embeds AppleScript in the notification's `execute` field:
- **iTerm2**: Uses `ITERM_SESSION_ID` env var (must strip `wXtXpX:` prefix to match AppleScript session IDs), falls back to TTY-based detection
- **Terminal.app**: Captures window/tab IDs via AppleScript
- **Other terminals** (Warp, Alacritty, kitty): Simple app activation

### Custom App Bundles

Each custom app (`grrr apps add`) is a full copy of growlrrr.app stored in `~/.growlrrr/apps/` with a distinct bundle ID (`com.moltenbits.growlrrr.{name}`) and custom icon. This gives each app its own entry in System Settings > Notifications. Icon conversion uses `sips` and `iconutil`.

### Shell Hooks (`grrr init`)

Generates shell-specific hooks (zsh `preexec`/`precmd`, bash `DEBUG` trap/`PROMPT_COMMAND`) that auto-notify when commands exceed a configurable time threshold.

## Installation Layout

- App bundle: `/Applications/growlrrr.app`
- CLI symlinks: `/usr/local/bin/growlrrr` and `/usr/local/bin/grrr` → bundle executable
- Custom apps: `~/.growlrrr/apps/{Name}.app`

## Dependencies

- **Runtime**: macOS 13.0+, plus system tools (`osascript`, `codesign`, `sips`, `iconutil`)
- **Build**: Swift 5.9+, [swift-argument-parser](https://github.com/apple/swift-argument-parser) 1.3.0+
