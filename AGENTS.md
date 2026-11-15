# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
make build              # Debug build (executable only)
make release            # Release build (executable only)
make bundle             # Debug app bundle (required for notifications to work)
make bundle-release     # Universal (arm64 + x86_64) release app bundle, as published
make bundle-release-native  # Release app bundle for this Mac's architecture only
make test               # Run tests
make install            # Build native release bundle, install to /Applications, create symlinks
make run                # Build debug bundle and send a test notification
make format             # Format code (requires swift-format)
make lint               # Lint code (requires swift-format)
```

All swift commands use `--disable-sandbox`. The app bundle is built via `scripts/bundle.sh [debug|release] [universal|native]` which compiles, creates the `.app` structure, generates shell completions, and code-signs. A release bundle is universal unless `native` is passed; published releases and CI use the universal build, `make install` the native one.

## Architecture

**growlrrr** is a macOS CLI tool that sends native notifications via the UserNotifications framework. It requires a proper `.app` bundle — bare executables cannot send notifications on macOS.

### Targets (Package.swift — Swift 5.9, macOS 13.0+)

- **`growlrrr`** (executable) — CLI entry point, depends on ArgumentParser and GrowlrrrCore
- **`GrowlrrrCore`** (library) — Shared models, custom app bundle management, reactivation methods
- **`GrowlrrrTests`** — XCTest suite testing models, bundle logic, and reactivation methods

### Key Source Files

| File | Purpose |
|------|---------|
| `Sources/growlrrr/Growlrrr.swift` | Main entry point (`GrowlrrrMain`) and all subcommands (`Send`, `List`, `Clear`, `Authorize`, `Apps`, `Init`) |
| `Sources/growlrrr/NotificationService.swift` | Async actor wrapping `UNUserNotificationCenter` — sending, waiting, listing, clearing |
| `Sources/GrowlrrrCore/CustomAppBundle.swift` | Creates/manages lightweight app bundles with custom icons in `~/.growlrrr/apps/` |
| `Sources/GrowlrrrCore/Models.swift` | `NotificationConfig`, `SoundOption`, `NotificationInfo`, `GrowlrrrError` |
| `Sources/GrowlrrrCore/Reactivation/` | `ReactivationMethod` protocol, `Reactivation` (chooses a method), `ReactivationContext`, and one class per terminal or app |

### Dual Launch Context

The app handles two launch modes in `GrowlrrrMain`:
1. **CLI invocation** — Parses arguments via ArgumentParser, runs the requested subcommand
2. **Notification click** — macOS relaunches the app; `NotificationLaunchHandler` (NSApplication delegate) executes embedded `execute`/`open` commands from the notification's userInfo

### Reactivation (`--reactivate`)

At send time growlrrr embeds a shell command in the notification's `execute` field; clicking the notification runs it. The command comes from a **reactivation method**: a `final class` in `Sources/GrowlrrrCore/Reactivation/` conforming to `ReactivationMethod` (`applies(in:)`, `clickCommand(in:)`, optional `promptSubmitted(in:)`).

- **Discovery.** `ReactivationMethods.discover()` finds every conforming class in the binary through the Objective-C runtime (`objc_copyClassNamesForImage`), so a method is one file with one `final class`. The protocol is `AnyObject`-constrained because only classes can be found this way.
- **Choosing a method.** `Reactivation` takes the methods that apply and uses the one in the innermost `ReactivationLayer` (`.terminal` < `.agentHost`). An agent host started from a terminal inherits the terminal's variables, so both apply and the agent host must win. Two applicable methods in one layer are a bug in the methods: one is picked by name and a warning is printed.
- **No method applies.** The click activates the nearest regular app among the sender's parent processes (`ReactivationContext.hostApp`), else the app named by `TERM_PROGRAM`.
- **A method that applies but returns nil** leaves the click without an action; it does not fall through to the host app.
- **`ReactivationContext`** carries the sender's environment, hook session id, tty, the frontmost app, a time-limited command runner, an AppleScript runner, shell quoting, and a per-method `ReactivationStore` (`~/.growlrrr/reactivation/<Method>/`). Tests build one from explicit parts with a fake runner.
- **Hook notifications.** `Reactivation.shouldNotify` asks the innermost method whether a hook belongs to a conversation; the default is true. T3 Code skips internal Codex jobs without an app thread. `hook notify` resolves the click before custom-app re-execution and passes `--execute`, since the inner `send` has no hook stdin.
- **Prompt submit.** `grrr hook dismiss` creates the context first (so `frontmostApp` is the app the prompt was typed into) and calls `Reactivation.promptSubmitted`, which reaches only the method that would handle the click.

User documentation for each application lives in its own page, `docs/reactivation/<application>.md`, linked from the "Reactivation" list in `README.md`. Keep application-specific and terminal-specific details out of `README.md`; it only describes reactivation in general and links to those pages. A new method comes with a new page.

The methods:
- **iTerm2** (`ITermReactivation`): Uses `ITERM_SESSION_ID` env var with iTerm2's `iterm2:reveal?sessionid=` URL — pass the full value unstripped (iTerm strips the `wXtXpX:` prefix itself) and use the opaque URL form (`iterm2:reveal`, not `iterm2:///reveal`). Finds sessions in minimized windows and avoids AppleScript z-order races. Falls back to TTY-based AppleScript detection (which matches the bare GUID, stripped) when the env var is absent
- **Terminal.app** (`TerminalAppReactivation`): Captures window/tab IDs via AppleScript
- **Ghostty** (`GhosttyReactivation`): Captures the focused terminal's id via AppleScript
- **Warp, Alacritty, kitty** (`NamedTerminalReactivation`): Simple app activation by name
- **T3 Code** (`T3CodeReactivation`, `.agentHost`): Recognises `T3CODE_THREAD_ID`, `T3CODE_CLI_PATH`, or `CODEX_INTERNAL_ORIGINATOR_OVERRIDE=T3`. Claude inherits the thread id; Codex hooks do not, so the method reads T3's local SQLite projection to match hook `session_id` to `nativeThreadRef.nativeId`. See `docs/reactivation/t3-code.md` for the schema and failure behavior. Runs `t3 thread show <id> --json` (CLI from `T3CODE_CLI_PATH`, else `t3` on `PATH`); `T3CodeThread` reads the environment and thread ids from the `link` field. Opens the thread in the desktop app (`open 't3code://threads/<environment>/<thread>'`), or, when a Safari "Add to Dock" web app is remembered for the thread, opens the hosted link in that web app (`open -a '<app>' '<link>'`). `promptSubmitted` does the remembering: a frontmost web app whose manifest `start_url` has the thread link's origin is stored, the desktop app clears the entry, any other app is ignored. If the thread can't be looked up the click does nothing

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
