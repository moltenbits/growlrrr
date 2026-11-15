import Foundation

public enum ITermSession {
    /// Allowed alphabet of an ITERM_SESSION_ID value (wXtXpX:UUID). The value
    /// is embedded in a `sh -c` command, so anything outside it is rejected.
    private static let sessionIdCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789:-")

    /// Builds the shell command that asks iTerm2 to reveal a session via its
    /// `iterm2:reveal?sessionid=` URL. Unlike the AppleScript window loop,
    /// the URL handler searches every terminal window — including minimized
    /// ones, which AppleScript's z-ordered `windows` list omits — and selects
    /// the window, tab, and pane atomically inside iTerm's process.
    ///
    /// Pass the full ITERM_SESSION_ID value: iTerm strips the wXtXpX: prefix
    /// itself, and treats a value with no colon as a silent no-op. The URL
    /// must stay in opaque form (`iterm2:reveal`, not `iterm2:///reveal`) —
    /// iTerm compares the URL path against the literal "reveal".
    public static func revealCommand(sessionId: String) -> String? {
        guard !sessionId.isEmpty,
              sessionId.contains(":"),
              sessionId.unicodeScalars.allSatisfy({ sessionIdCharacters.contains($0) }) else {
            return nil
        }
        return "open 'iterm2:reveal?sessionid=\(sessionId)'"
    }
}
