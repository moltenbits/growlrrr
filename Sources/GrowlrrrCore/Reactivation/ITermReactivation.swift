import Foundation

/// iTerm2: returns to the exact session, by the most reliable means on hand.
public final class ITermReactivation: ReactivationMethod {
    public init() {}

    public func applies(in context: ReactivationContext) -> Bool {
        context.environment["TERM_PROGRAM"] == "iTerm.app"
    }

    public func clickCommand(in context: ReactivationContext) -> String? {
        // Strategy 1: Use ITERM_SESSION_ID environment variable with iTerm2's
        // reveal URL. iTerm2 sets the variable directly in every session, and
        // the URL handler finds the session even when its window is minimized
        // or the z-order shifts mid-script — the AppleScript loop below can
        // land on the wrong window in both cases.
        if let sessionId = context.environment["ITERM_SESSION_ID"],
           let revealCommand = ITermSession.revealCommand(sessionId: sessionId) {
            return revealCommand
        }

        // Strategy 2: Use tty path to identify the session.
        // Completely independent of iTerm2's window/session naming.
        if let tty = context.tty {
            return selectSession(where: "tty of s is \"\(tty)\"")
        }

        // Strategy 3: Ask iTerm2 which session is current (works when no
        // custom window name).
        if let sessionId = context.appleScript(
            "tell application \"iTerm2\" to id of current session of current window") {
            return selectSession(where: "id of s is \"\(sessionId)\"")
        }

        return "osascript -e 'tell application \"iTerm2\" to activate'"
    }

    private func selectSession(where condition: String) -> String {
        // Use heredoc to preserve newlines which AppleScript requires.
        // activate must come before select so the tab switch isn't
        // clobbered by the focus transition from Notification Center.
        return """
            osascript <<'APPLESCRIPT'
            tell application "iTerm2"
                activate
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if \(condition) then
                                select w
                                select t
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            APPLESCRIPT
            """
    }
}
