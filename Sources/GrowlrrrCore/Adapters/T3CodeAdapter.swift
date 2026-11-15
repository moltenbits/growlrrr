import Foundation

/// T3 Code: returns to the thread the agent is running in.
///
/// Claude inherits `T3CODE_THREAD_ID`; Codex hooks instead identify their
/// session on stdin, which T3 Code's local state associates with a thread.
/// The thread can be shown by the T3 Code desktop app, or by any number of
/// Safari "Add to Dock" web apps made from T3 Code's site — someone may keep
/// several, each filtered to one project. Nothing ties a thread to one of
/// those, so this adapter remembers which one each thread was last prompted
/// from and returns there.
public final class T3CodeAdapter: ApplicationAdapter {
    /// A T3 Code server started from a terminal passes that terminal's
    /// variables on to its agents; the thread is still where to return to.
    public static let layer = AdapterLayer.agentApp

    /// How long to wait for `t3 thread show`.
    private static let lookupTimeout: TimeInterval = 5

    public init() {}

    public func applies(in context: AdapterContext) -> Bool {
        explicitThreadId(in: context) != nil
            || !(context.environment["T3CODE_CLI_PATH"] ?? "").isEmpty
            || context.environment["CODEX_INTERNAL_ORIGINATOR_OVERRIDE"] == "T3"
    }

    /// T3 Code also runs Codex for internal jobs such as generating titles.
    /// Their sessions have no app thread and should not send notifications.
    /// A failed lookup preserves the notification, without a click action.
    public func shouldNotify(in context: AdapterContext) -> Bool {
        guard explicitThreadId(in: context) == nil,
              let threads = codexThreadIds(in: context) else {
            return true
        }
        return !threads.isEmpty
    }

    /// Opens the thread in the web app remembered for it, or in the desktop
    /// app when none is remembered. A thread that cannot be looked up gets
    /// no click action: activating T3 Code without a thread is not a return
    /// to anywhere in particular.
    public func clickCommand(in context: AdapterContext) -> String? {
        guard let threadId = threadId(in: context),
              let thread = lookUpThread(threadId, in: context) else {
            return nil
        }
        if let webApp = context.store(for: self).value(forKey: threadId),
           FileManager.default.fileExists(atPath: webApp) {
            return thread.webAppRevealCommand(appPath: webApp)
        }
        return thread.desktopAppRevealCommand
    }

    /// Notes which T3 Code client the prompt was typed into, going by the
    /// app that was frontmost:
    /// - a web app made from the thread's site is remembered for the thread;
    /// - the desktop app clears what was remembered, since the desktop app
    ///   is where a click leads by default;
    /// - any other app changes nothing, because nobody typed the prompt
    ///   into it (a queued or scheduled prompt).
    public func promptSubmitted(in context: AdapterContext) {
        guard let threadId = threadId(in: context),
              let frontmostApp = context.frontmostApp?.standardizedFileURL else {
            return
        }
        let store = context.store(for: self)

        if let anyThread = URL(string: "t3code://threads"),
           context.application(handling: anyThread)?.standardizedFileURL == frontmostApp {
            store.removeValue(forKey: threadId)
            return
        }

        // Checked before the CLI lookup so that prompts typed into an
        // ordinary app, or into the web app already remembered, cost nothing.
        let infoPlist = frontmostApp.appendingPathComponent("Contents/Info.plist")
        guard let infoPlistData = try? Data(contentsOf: infoPlist),
              let webAppOrigin = T3CodeThread.webAppOrigin(infoPlist: infoPlistData),
              store.value(forKey: threadId) != frontmostApp.path else {
            return
        }

        guard let thread = lookUpThread(threadId, in: context), thread.origin == webAppOrigin else {
            return
        }
        try? store.set(frontmostApp.path, forKey: threadId)
    }

    private func threadId(in context: AdapterContext) -> String? {
        if let threadId = explicitThreadId(in: context) {
            return threadId
        }
        guard let threads = codexThreadIds(in: context), threads.count == 1 else {
            return nil
        }
        return threads[0]
    }

    private func explicitThreadId(in context: AdapterContext) -> String? {
        guard let threadId = context.environment["T3CODE_THREAD_ID"], !threadId.isEmpty else {
            return nil
        }
        return threadId
    }

    /// The CLI does not expose lookup by provider session. Read only the
    /// existing local projection; never guess from cwd or modify T3's state.
    /// `provider_session_id` identifies the shared app-server, whereas
    /// nativeThreadRef.nativeId is the Codex session in hook stdin.
    /// Nil means unavailable/changed schema; an empty array means no thread.
    private func codexThreadIds(in context: AdapterContext) -> [String]? {
        guard let sessionId = context.hookSessionId, !sessionId.isEmpty,
              !sessionId.contains("\0") else {
            return nil
        }
        let home: URL
        if let path = context.environment["T3CODE_HOME"], !path.isEmpty {
            home = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        } else {
            home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".t3")
        }
        let database = home.appendingPathComponent("userdata/statev2.sqlite")
        let session = sessionId.replacingOccurrences(of: "'", with: "''")
        let query = """
            SELECT json_group_array(thread_id) FROM (
                SELECT DISTINCT thread_id
                FROM orchestration_v2_projection_provider_threads
                WHERE provider = 'codex' AND owner_node_id IS NULL
                  AND thread_id IS NOT NULL AND thread_id != ''
                  AND json_extract(payload_json, '$.nativeThreadRef.nativeId') = '\(session)'
                LIMIT 2
            );
            """
        guard let output = context.run("/usr/bin/sqlite3",
            ["-init", "/dev/null", "-readonly", "-batch", database.path, query],
            timeout: Self.lookupTimeout) else {
            return nil
        }
        return try? JSONDecoder().decode([String].self, from: output)
    }

    /// Asks the t3 CLI for the thread. T3 Code usually names its own CLI in
    /// `T3CODE_CLI_PATH`; otherwise whichever `t3` is on `PATH` is used.
    private func lookUpThread(_ threadId: String, in context: AdapterContext) -> T3CodeThread? {
        let showThread = ["thread", "show", threadId, "--json", "--messages", "0"]
        let output: Data?
        if let cli = context.environment["T3CODE_CLI_PATH"], !cli.isEmpty {
            output = context.run(cli, showThread, timeout: Self.lookupTimeout)
        } else {
            output = context.run("/usr/bin/env", ["t3"] + showThread, timeout: Self.lookupTimeout)
        }
        return output.flatMap(T3CodeThread.init(threadShowOutput:))
    }
}
