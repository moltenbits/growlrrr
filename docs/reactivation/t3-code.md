# T3 Code

Clicking a notification sent by an agent that T3 Code runs opens the thread the agent is running in. T3 Code is not a terminal, so there is no terminal window to return to.

The Claude Code and Codex hook integrations described in the main README work unchanged for agents run by T3 Code.

## How it works

Claude Code inherits its T3 thread id in `T3CODE_THREAD_ID`. T3 Code gives Codex that variable through `shell_environment_policy.set`, but Codex does not pass that setting to hook commands ([upstream issue](https://github.com/openai/codex/issues/40325)). Codex hooks instead provide their Codex `session_id` on stdin.

growlrrr recognises T3 Code through `T3CODE_THREAD_ID`, `T3CODE_CLI_PATH`, or Codex's `CODEX_INTERNAL_ORIGINATOR_OVERRIDE=T3`. When the thread id is absent, `T3CodeReactivation` matches the hook's session id against T3's local provider-thread records. It reads `$T3CODE_HOME/userdata/statev2.sqlite` (default `~/.t3/userdata/statev2.sqlite`) with the system SQLite CLI in read-only mode. The matching value is `nativeThreadRef.nativeId` in `orchestration_v2_projection_provider_threads.payload_json`; `provider_session_id` identifies the shared Codex app-server and cannot identify a conversation. growlrrr requires one distinct app thread and never guesses from the working directory.

Once the thread is identified, growlrrr looks it up with `t3 thread show <id> --json`, using the CLI named in `T3CODE_CLI_PATH`, or `t3` on `PATH` when that is not set. Each command lookup is limited to 5 seconds.

By default the click opens the thread in the T3 Code desktop app, through its `t3code://threads/<environment>/<thread>` link.

If the state cannot be read, the mapping is ambiguous, or the thread cannot be looked up, the notification is still sent but clicking it does nothing. It never falls back to activating T3 Code or an inherited terminal without a thread.

## Codex title notifications

T3 Code generates titles with a separate, ephemeral Codex process in the project directory. That process runs the project's Stop hook too, with a JSON title as its last assistant message. Its Codex session has no app thread, so growlrrr skips the notification when a successful state lookup finds no thread. This also applies with `--no-reactivate` and custom apps. It does not filter message contents: a real conversation that replies with JSON still notifies.

## Safari web apps

T3 Code can also be used through Safari "Add to Dock" web apps, and several can be made from the same site, for example one per project, each with its own filters. The click then opens the thread in the web app you last prompted it from:

- When you submit a prompt, `grrr hook dismiss` looks at the frontmost app. If it is a web app made from the same site as the thread's link, growlrrr remembers that web app for the thread, in `~/.growlrrr/reactivation/T3CodeReactivation/`.
- When the turn ends, `grrr hook notify` builds the click action from what was remembered, so the notification brings that web app forward on the thread.
- With `--appId`, the hook resolves the click action before handing the notification to the custom bundle, preserving the session information from stdin.
- Prompting the thread from a different web app replaces what was remembered. Prompting it from the desktop app clears it, so notifications lead to the desktop app again.
- A prompt submitted while some other app is frontmost (a queued or scheduled prompt) changes nothing.

This needs both hooks: `grrr hook dismiss` on prompt submit and `grrr hook notify` on turn end, as `grrr init` generates them.

## Limits

- Opening a thread's link in a web app makes the web app load the page again, even if it was already showing that thread.
- If the T3 Code server was started from a terminal (`t3` run in a terminal tab), the agent also carries that terminal's variables. The thread still wins: the click opens the thread, not the terminal tab.
- The Codex session lookup uses T3 Code's internal local schema because its CLI does not expose lookup by provider session. A missing database or incompatible schema preserves notifications but disables their click action. A successful lookup with no matching app thread suppresses the notification.
- `--message` deliberately skips stdin unless a `--gate` needs it. Without the hook's session id or `T3CODE_THREAD_ID`, growlrrr cannot identify the thread or distinguish an internal job; the notification is sent without a click action. When a gate reads stdin, the session is retained even with a message override.

## Permissions

None.

## Implementation

`T3CodeReactivation` and `T3CodeThread` in `Sources/GrowlrrrCore/Reactivation/`.
