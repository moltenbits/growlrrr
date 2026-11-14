import Foundation

/// T3 Code: returns to the thread the agent is running in.
///
/// T3 Code starts every agent with its thread id in `T3CODE_THREAD_ID`. The
/// thread can be shown by the T3 Code desktop app, or by any number of
/// Safari "Add to Dock" web apps made from T3 Code's site — someone may keep
/// several, each filtered to one project. Nothing ties a thread to one of
/// those, so this method remembers which one each thread was last prompted
/// from and returns there.
public final class T3CodeReactivation: ReactivationMethod {
    /// A T3 Code server started from a terminal passes that terminal's
    /// variables on to its agents; the thread is still where to return to.
    public static let layer = ReactivationLayer.agentHost

    /// How long to wait for `t3 thread show`.
    private static let lookupTimeout: TimeInterval = 5

    public init() {}

    public func applies(in context: ReactivationContext) -> Bool {
        threadId(in: context) != nil
    }

    /// Opens the thread in the web app remembered for it, or in the desktop
    /// app when none is remembered. A thread that cannot be looked up gets
    /// no click action: activating T3 Code without a thread is not a return
    /// to anywhere in particular.
    public func clickCommand(in context: ReactivationContext) -> String? {
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
    public func promptSubmitted(in context: ReactivationContext) {
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

    private func threadId(in context: ReactivationContext) -> String? {
        guard let threadId = context.environment["T3CODE_THREAD_ID"], !threadId.isEmpty else {
            return nil
        }
        return threadId
    }

    /// Asks the t3 CLI for the thread. T3 Code usually names its own CLI in
    /// `T3CODE_CLI_PATH`; otherwise whichever `t3` is on `PATH` is used.
    private func lookUpThread(_ threadId: String, in context: ReactivationContext) -> T3CodeThread? {
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
