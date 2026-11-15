import Foundation

/// Ghostty: returns to the terminal that was focused when the notification
/// was sent.
public final class GhosttyAdapter: ApplicationAdapter {
    public init() {}

    public func applies(in context: AdapterContext) -> Bool {
        context.environment["TERM_PROGRAM"] == "ghostty"
    }

    public func clickCommand(in context: AdapterContext) -> String? {
        // Capture the focused terminal's UUID via AppleScript
        guard let terminalId = context.appleScript("""
            tell application "Ghostty"
                set term to focused terminal of selected tab of front window
                return id of term
            end tell
            """) else {
            return "osascript -e 'tell application \"Ghostty\" to activate'"
        }

        return """
            osascript <<'APPLESCRIPT'
            tell application "Ghostty"
                activate
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with term in terminals of t
                            if id of term is "\(terminalId)" then
                                focus term
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
