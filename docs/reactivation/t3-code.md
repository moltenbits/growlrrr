# T3 Code

Clicking a notification sent by an agent that T3 Code runs opens the thread the agent is running in. T3 Code is not a terminal, so there is no terminal window to return to.

The Claude Code and Codex hook integrations described in the main README work unchanged for agents run by T3 Code.

## How it works

T3 Code starts every agent with its thread id in `T3CODE_THREAD_ID`, which is how growlrrr recognises it. While the notification is being sent, growlrrr looks the thread up with `t3 thread show <id> --json`, using the CLI named in `T3CODE_CLI_PATH`, or `t3` on `PATH` when that is not set. The lookup is limited to 5 seconds.

By default the click opens the thread in the T3 Code desktop app, through its `t3code://threads/<environment>/<thread>` link.

If the thread cannot be looked up, the notification is still sent but clicking it does nothing.

## Safari web apps

T3 Code can also be used through Safari "Add to Dock" web apps, and several can be made from the same site, for example one per project, each with its own filters. The click then opens the thread in the web app you last prompted it from:

- When you submit a prompt, `grrr hook dismiss` looks at the frontmost app. If it is a web app made from the same site as the thread's link, growlrrr remembers that web app for the thread, in `~/.growlrrr/reactivation/T3CodeReactivation/`.
- When the turn ends, `grrr hook notify` builds the click action from what was remembered, so the notification brings that web app forward on the thread.
- Prompting the thread from a different web app replaces what was remembered. Prompting it from the desktop app clears it, so notifications lead to the desktop app again.
- A prompt submitted while some other app is frontmost (a queued or scheduled prompt) changes nothing.

This needs both hooks: `grrr hook dismiss` on prompt submit and `grrr hook notify` on turn end, as `grrr init` generates them.

## Limits

- Opening a thread's link in a web app makes the web app load the page again, even if it was already showing that thread.
- If the T3 Code server was started from a terminal (`t3` run in a terminal tab), the agent also carries that terminal's variables. The thread still wins: the click opens the thread, not the terminal tab.

## Permissions

None.

## Implementation

`T3CodeReactivation` and `T3CodeThread` in `Sources/GrowlrrrCore/Reactivation/`.
