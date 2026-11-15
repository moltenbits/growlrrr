import AppKit
import Foundation

/// What an adapter can find out about where a notification is
/// being sent from, and the helpers it shares with every other adapter.
public struct AdapterContext {
    /// Runs an executable and returns what it printed, or nil if it could
    /// not be started, exited with an error, or outlasted the timeout.
    public typealias CommandRunner =
        (_ executable: String, _ arguments: [String], _ timeout: TimeInterval?) -> Data?

    /// Environment variables of the process that is sending the
    /// notification, inherited from the terminal or app it runs in.
    public let environment: [String: String]

    /// The agent's session id from hook stdin, before notification identity
    /// overrides such as GROWLRRR_SESSION_ID or --appId are applied. Added
    /// after reading stdin so the frontmost app can be captured first.
    public var hookSessionId: String?

    /// The app bundle that was frontmost when growlrrr started. When a
    /// prompt has just been submitted, this is the app it was typed into.
    public let frontmostApp: URL?

    /// The terminal device growlrrr's input is attached to, if any.
    public let tty: String?

    private let stateDirectory: URL
    private let parentAppLookup: () -> URL?
    private let urlHandlerLookup: (URL) -> URL?
    private let runner: CommandRunner

    /// Builds a context from explicit parts, for tests.
    public init(
        environment: [String: String] = [:],
        frontmostApp: URL? = nil,
        tty: String? = nil,
        stateDirectory: URL,
        parentApp: @escaping () -> URL? = { nil },
        applicationHandling: @escaping (URL) -> URL? = { _ in nil },
        run: @escaping CommandRunner = { _, _, _ in nil }
    ) {
        self.environment = environment
        self.frontmostApp = frontmostApp
        self.tty = tty
        self.stateDirectory = stateDirectory
        self.parentAppLookup = parentApp
        self.urlHandlerLookup = applicationHandling
        self.runner = run
    }

    /// The context of this process. Create it before doing anything slow,
    /// so `frontmostApp` reflects the moment growlrrr was started.
    public static func live() -> AdapterContext {
        AdapterContext(
            environment: ProcessInfo.processInfo.environment,
            frontmostApp: NSWorkspace.shared.frontmostApplication?.bundleURL,
            tty: isatty(STDIN_FILENO) != 0 ? ttyname(STDIN_FILENO).map { String(cString: $0) } : nil,
            stateDirectory: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".growlrrr")
                .appendingPathComponent("adapters"),
            parentApp: findParentApp,
            applicationHandling: { NSWorkspace.shared.urlForApplication(toOpen: $0) },
            run: runCommand)
    }

    /// The nearest regular app among the parents of this process: the
    /// terminal, editor, or other app that the sender is running inside.
    public var parentApp: URL? {
        parentAppLookup()
    }

    /// The app that opens URLs like the given one, e.g. one with a custom
    /// scheme.
    public func application(handling url: URL) -> URL? {
        urlHandlerLookup(url)
    }

    /// Runs an executable and returns what it printed. Pass a timeout for
    /// anything that could hang: the hook that started growlrrr is waiting.
    public func run(_ executable: String, _ arguments: [String], timeout: TimeInterval? = nil) -> Data? {
        runner(executable, arguments, timeout)
    }

    /// Runs an AppleScript and returns what it printed, trimmed, or nil if
    /// it failed or printed nothing. There is no timeout: the first script
    /// sent to an app waits on macOS's Automation permission prompt.
    public func appleScript(_ source: String) -> String? {
        guard let output = run("/usr/bin/osascript", ["-e", source]) else {
            return nil
        }
        let result = String(decoding: output, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    /// The adapter's own store, under `~/.growlrrr/adapters/<adapter>/`.
    public func store(for adapter: ApplicationAdapter) -> AdapterStore {
        AdapterStore(
            directory: stateDirectory.appendingPathComponent(String(describing: type(of: adapter))))
    }

    /// Quotes a value for use as one word of a `sh -c` command.
    public static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    // MARK: - This process

    private static func runCommand(executable: String, arguments: [String], timeout: TimeInterval?) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        // Read while the command runs: one that prints more than a pipe
        // holds would otherwise never exit.
        var output = Data()
        let reading = DispatchGroup()
        DispatchQueue.global().async(group: reading) {
            output = pipe.fileHandleForReading.readDataToEndOfFile()
        }

        if let timeout {
            guard reading.wait(timeout: .now() + timeout) == .success else {
                process.terminate()
                return nil
            }
        } else {
            reading.wait()
        }

        process.waitUntilExit()
        return process.terminationStatus == 0 ? output : nil
    }

    private static func findParentApp() -> URL? {
        var pid = getppid()
        while pid > 1 {
            if let app = NSRunningApplication(processIdentifier: pid),
               app.activationPolicy == .regular,
               let bundle = app.bundleURL {
                return bundle
            }
            guard let parent = parentProcess(of: pid), parent != pid else {
                return nil
            }
            pid = parent
        }
        return nil
    }

    private static func parentProcess(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&name, UInt32(name.count), &info, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        return info.kp_eproc.e_ppid
    }
}
