import Foundation

/// Terminal.app: returns to the window and tab that were in front when the
/// notification was sent.
public final class TerminalAppAdapter: ApplicationAdapter {
    public init() {}

    public func applies(in context: AdapterContext) -> Bool {
        context.environment["TERM_PROGRAM"] == "Apple_Terminal"
    }

    public func clickCommand(in context: AdapterContext) -> String? {
        let activate = "osascript -e 'tell application \"Terminal\" to activate'"

        // Capture the current Terminal.app window and tab
        guard let captured = context.appleScript("""
            tell application "Terminal"
                set windowId to id of front window
                set tabIndex to index of selected tab of front window
                return (windowId as text) & "," & (tabIndex as text)
            end tell
            """) else {
            return activate
        }

        let parts = captured.split(separator: ",")
        guard parts.count == 2, let windowId = Int(parts[0]), let tabIndex = Int(parts[1]) else {
            return activate
        }

        // Generate AppleScript that finds and focuses this specific window/tab
        // Use heredoc to preserve newlines which AppleScript requires
        return """
            osascript <<'APPLESCRIPT'
            tell application "Terminal"
                repeat with w in windows
                    if id of w is \(windowId) then
                        set selected tab of w to tab \(tabIndex) of w
                        set frontmost of w to true
                        activate
                        return
                    end if
                end repeat
            end tell
            APPLESCRIPT
            """
    }
}
