public enum HookSession {
    /// Derives the session discriminator used in hook notification
    /// identifiers (`growlrrr-hook-{sessionId}`).
    ///
    /// Precedence: GROWLRRR_SESSION_ID env var, then the `session_id` from
    /// the hook's stdin JSON, then appId, then "default". The env var wins
    /// because the shell hooks autoclear `growlrrr-hook-$GROWLRRR_SESSION_ID`.
    /// The stdin session_id comes before appId so that concurrent Claude Code
    /// sessions sharing an app get distinct identifiers — otherwise each
    /// notification silently replaces the previous one and clicking it
    /// reactivates the wrong terminal window.
    public static func derive(
        environmentSessionId: String?,
        stdinSessionId: String?,
        appId: String?
    ) -> String {
        for candidate in [environmentSessionId, stdinSessionId, appId] {
            if let candidate = candidate, !candidate.isEmpty {
                return candidate
            }
        }
        return "default"
    }
}
