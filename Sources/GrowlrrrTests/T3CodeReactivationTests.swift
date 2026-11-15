import XCTest
import GrowlrrrCore

final class T3CodeReactivationTests: XCTestCase {

    private let threadId = "962887c7-9d48-4440-99bd-0461933b8033"
    private let desktopCommand =
        "open 't3code://threads/7e9a75d0-3c28-48ef-a9f3-9551e82938b6/962887c7-9d48-4440-99bd-0461933b8033'"

    private var scratch: URL!
    /// `t3` CLI invocations, as [executable, arguments..., "timeout=<seconds>"].
    private var commandsRun: [[String]] = []
    /// What the `t3` CLI prints; nil makes it fail.
    private var threadLink: String? =
        "https://app.t3.codes/threads/7e9a75d0-3c28-48ef-a9f3-9551e82938b6/962887c7-9d48-4440-99bd-0461933b8033"

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("growlrrr-t3code-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        commandsRun = []
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    // MARK: - Fixtures

    private var desktopApp: URL { scratch.appendingPathComponent("T3 Code (Beta).app") }

    /// An app bundle on disk. With a start URL it is a Safari "Add to Dock"
    /// web app, whose Info.plist carries the site's web manifest.
    private func makeApp(named name: String, webAppStartURL: String? = nil) throws -> URL {
        let app = scratch.appendingPathComponent("\(name).app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var plist: [String: Any] = ["CFBundleName": name]
        if let webAppStartURL {
            plist["Manifest"] = ["start_url": webAppStartURL, "display": "standalone"]
        }
        try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }

    private func context(
        threadId: String? = nil,
        environment: [String: String] = ["T3CODE_CLI_PATH": "/Users/me/.t3/bin/t3"],
        frontmostApp: URL? = nil,
        hookSessionId: String? = nil
    ) -> ReactivationContext {
        var environment = environment
        environment["T3CODE_THREAD_ID"] = threadId ?? self.threadId
        var context = ReactivationContext(
            environment: environment,
            frontmostApp: frontmostApp,
            stateDirectory: scratch.appendingPathComponent("state"),
            applicationHandling: { $0.scheme == "t3code" ? self.desktopApp : nil },
            run: { executable, arguments, timeout in
                self.commandsRun.append(
                    [executable] + arguments + ["timeout=\(timeout.map { String($0) } ?? "none")"])
                if executable == "/usr/bin/sqlite3" {
                    return self.runSQLite(arguments)
                }
                guard let link = self.threadLink else {
                    return nil
                }
                let json: [String: Any] = ["thread": ["link": link], "messages": []]
                return try? JSONSerialization.data(withJSONObject: json)
            })
        context.hookSessionId = hookSessionId
        return context
    }

    private func runSQLite(_ arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? output : nil
    }

    private var t3Database: URL { scratch.appendingPathComponent("userdata/statev2.sqlite") }

    private func makeT3Database() throws {
        try FileManager.default.createDirectory(at: t3Database.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        // Relevant columns from T3 Code's provider-thread projection. The
        // Codex session is nativeThreadRef.nativeId, NOT provider_session_id
        // (which identifies the shared app-server process).
        XCTAssertNotNil(runSQLite([t3Database.path, """
            CREATE TABLE orchestration_v2_projection_provider_threads (
                thread_id TEXT, provider TEXT, owner_node_id TEXT, payload_json TEXT NOT NULL
            );
            """]))
    }

    private func addCodexSession(_ session: String, thread: String, provider: String = "codex") throws {
        let payload = try JSONSerialization.data(withJSONObject: ["nativeThreadRef": ["nativeId": session]])
        func quoted(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "''") + "'" }
        XCTAssertNotNil(runSQLite([t3Database.path, """
            INSERT INTO orchestration_v2_projection_provider_threads VALUES (
                \(quoted(thread)), \(quoted(provider)), NULL, \(quoted(String(decoding: payload, as: UTF8.self)))
            );
            """]))
    }

    private func codexContext(session: String? = "codex-session", frontmostApp: URL? = nil) -> ReactivationContext {
        context(threadId: "", environment: [
            "T3CODE_CLI_PATH": "/Users/me/.t3/bin/t3", "T3CODE_HOME": scratch.path,
        ], frontmostApp: frontmostApp, hookSessionId: session)
    }

    func testCodexHookFindsItsExactThreadAndRemembersThePromptingWebApp() throws {
        try makeT3Database()
        try addCodexSession("other-session", thread: "other-thread")
        try addCodexSession("codex-session", thread: threadId)
        let webApp = try makeApp(named: "T3 Code (Growlrrr)", webAppStartURL: "https://app.t3.codes/")
        let reactivation = Reactivation(methods: [T3CodeReactivation()])

        reactivation.promptSubmitted(in: codexContext(frontmostApp: webApp))

        XCTAssertTrue(reactivation.shouldNotify(in: codexContext()))
        XCTAssertEqual(reactivation.clickCommand(in: codexContext()),
            "open -a '\(webApp.path)' 'https://app.t3.codes/threads/7e9a75d0-3c28-48ef-a9f3-9551e82938b6/\(threadId)'")
        XCTAssertTrue(commandsRun.contains { $0.contains("show") && $0.contains(threadId) })
        XCTAssertFalse(commandsRun.contains { $0.contains("show") && $0.contains("other-thread") })
    }

    func testT3TitleGenerationWithoutAnAppThreadDoesNotNotify() throws {
        try makeT3Database()
        try addCodexSession("real-session", thread: threadId)
        let reactivation = Reactivation(methods: [T3CodeReactivation()])

        XCTAssertFalse(reactivation.shouldNotify(in: codexContext(session: "ephemeral-title-session")))
        XCTAssertNil(reactivation.clickCommand(in: codexContext(session: "ephemeral-title-session")))
    }

    func testUnreadableT3StatePreservesTheNotificationButLeavesTheClickWithoutAnAction() throws {
        let reactivation = Reactivation(methods: [T3CodeReactivation()])
        XCTAssertTrue(reactivation.shouldNotify(in: codexContext()))
        XCTAssertNil(reactivation.clickCommand(in: codexContext()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: t3Database.path), "Lookup must not create a database")

        try FileManager.default.createDirectory(at: t3Database.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("not a sqlite database".utf8).write(to: t3Database)
        XCTAssertTrue(reactivation.shouldNotify(in: codexContext()))
        XCTAssertNil(reactivation.clickCommand(in: codexContext()))
    }

    func testAmbiguousCodexSessionNeverChoosesAnArbitraryThread() throws {
        try makeT3Database()
        try addCodexSession("codex-session", thread: threadId)
        try addCodexSession("codex-session", thread: "another-thread")
        let reactivation = Reactivation(methods: [T3CodeReactivation()])

        XCTAssertTrue(reactivation.shouldNotify(in: codexContext()))
        XCTAssertNil(reactivation.clickCommand(in: codexContext()))
    }

    func testCodexSessionLookupDoesNotMatchAnotherProviderOrInterpretSQL() throws {
        try makeT3Database()
        try addCodexSession("codex-session", thread: "claude-thread", provider: "claudeAgent")
        let reactivation = Reactivation(methods: [T3CodeReactivation()])

        XCTAssertNil(reactivation.clickCommand(in: codexContext()))
        XCTAssertNil(reactivation.clickCommand(in: codexContext(session: "' OR 1=1 --")))
    }

    func testAnExplicitThreadTakesPrecedenceOverTheCodexSession() {
        let context = context(hookSessionId: "codex-session")
        let reactivation = Reactivation(methods: [T3CodeReactivation()])

        XCTAssertTrue(reactivation.shouldNotify(in: context))
        XCTAssertEqual(reactivation.clickCommand(in: context), desktopCommand)
        XCTAssertFalse(commandsRun.contains { $0.first == "/usr/bin/sqlite3" })
    }

    func testNotificationsWithoutAHookSessionAreNotSuppressed() {
        let reactivation = Reactivation(methods: [T3CodeReactivation()])
        XCTAssertTrue(reactivation.shouldNotify(in: codexContext(session: nil)))
        XCTAssertTrue(reactivation.shouldNotify(in: ReactivationContext(stateDirectory: scratch)))
    }

    // MARK: - Recognising a T3 Code thread

    func testAppliesToAnAgentRunningInAT3CodeThread() {
        let method = T3CodeReactivation()
        let anywhere = ReactivationContext(stateDirectory: scratch)
        let emptyThreadId = ReactivationContext(
            environment: ["T3CODE_THREAD_ID": ""], stateDirectory: scratch)

        XCTAssertTrue(method.applies(in: context()))
        XCTAssertFalse(method.applies(in: anywhere))
        XCTAssertFalse(method.applies(in: emptyThreadId))
    }

    func testIsDiscoveredAsAnAgentHost() {
        let discovered = ReactivationMethods.discover().map { String(describing: type(of: $0)) }

        XCTAssertTrue(discovered.contains("T3CodeReactivation"), "discovered: \(discovered.sorted())")
        XCTAssertEqual(T3CodeReactivation.layer, .agentHost)
    }

    func testWinsOverTheTerminalTheT3ServerWasStartedFrom() {
        // `t3` run in an iTerm2 tab: agents inherit iTerm2's variables too.
        var environment = ["T3CODE_CLI_PATH": "/Users/me/.t3/bin/t3"]
        environment["TERM_PROGRAM"] = "iTerm.app"
        environment["ITERM_SESSION_ID"] = "w0t0p0:15D2E73B-2807-4ED8-8DA2-19AEC7D862B0"
        var warnings: [String] = []
        let reactivation = Reactivation(
            methods: [ITermReactivation(), T3CodeReactivation()], warn: { warnings.append($0) })

        XCTAssertEqual(reactivation.clickCommand(in: context(environment: environment)), desktopCommand)
        XCTAssertEqual(warnings, [])
    }

    // MARK: - The click command

    func testOpensTheThreadInTheDesktopAppByDefault() {
        XCTAssertEqual(T3CodeReactivation().clickCommand(in: context()), desktopCommand)
    }

    func testLooksTheThreadUpWithT3CodesOwnCLIUnderATimeout() {
        _ = T3CodeReactivation().clickCommand(in: context())

        XCTAssertEqual(commandsRun, [[
            "/Users/me/.t3/bin/t3", "thread", "show", threadId, "--json", "--messages", "0", "timeout=5.0",
        ]])
    }

    func testLooksTheThreadUpWithT3OnThePathWhenNoCLIIsNamed() {
        _ = T3CodeReactivation().clickCommand(in: context(environment: [:]))

        XCTAssertEqual(commandsRun, [[
            "/usr/bin/env", "t3", "thread", "show", threadId, "--json", "--messages", "0", "timeout=5.0",
        ]])
    }

    func testAClickDoesNothingWhenTheThreadCannotBeLookedUp() {
        threadLink = nil
        XCTAssertNil(T3CodeReactivation().clickCommand(in: context()))

        threadLink = "https://app.t3.codes/new"
        XCTAssertNil(T3CodeReactivation().clickCommand(in: context()))
    }

    func testAnUnresolvedThreadDoesNotFallBackToActivatingTheHostApp() {
        threadLink = nil
        let underT3Code = ReactivationContext(
            environment: ["T3CODE_THREAD_ID": threadId],
            stateDirectory: scratch,
            hostApp: { self.desktopApp })

        XCTAssertNil(Reactivation(methods: [T3CodeReactivation()]).clickCommand(in: underT3Code))
    }

    func testAT3CodeHookWithoutAThreadDoesNotActivateTheDesktopAppOrInheritedTerminal() {
        let underT3Code = ReactivationContext(
            environment: ["T3CODE_CLI_PATH": "/Users/me/.t3/bin/t3", "TERM_PROGRAM": "iTerm.app"],
            stateDirectory: scratch,
            hostApp: { self.desktopApp })

        XCTAssertTrue(T3CodeReactivation().applies(in: underT3Code))
        XCTAssertNil(Reactivation(methods: [T3CodeReactivation(), ITermReactivation()])
            .clickCommand(in: underT3Code))
    }

    // MARK: - Remembering the web app a prompt came from

    func testOpensTheThreadInTheWebAppItWasPromptedFrom() throws {
        let webApp = try makeApp(named: "T3 Code (Growlrrr)", webAppStartURL: "https://app.t3.codes/")
        let method = T3CodeReactivation()

        method.promptSubmitted(in: context(frontmostApp: webApp))

        XCTAssertEqual(
            method.clickCommand(in: context()),
            "open -a '\(webApp.path)' 'https://app.t3.codes/threads/7e9a75d0-3c28-48ef-a9f3-9551e82938b6/962887c7-9d48-4440-99bd-0461933b8033'")
    }

    func testAPromptFromAnotherWebAppReplacesTheRememberedOne() throws {
        let growlrrr = try makeApp(named: "T3 Code (Growlrrr)", webAppStartURL: "https://app.t3.codes/")
        let listenly = try makeApp(named: "T3 Code (Listenly)", webAppStartURL: "https://app.t3.codes/")
        let method = T3CodeReactivation()

        method.promptSubmitted(in: context(frontmostApp: growlrrr))
        method.promptSubmitted(in: context(frontmostApp: listenly))

        XCTAssertTrue(method.clickCommand(in: context())?.hasPrefix("open -a '\(listenly.path)'") ?? false)
    }

    func testEachThreadRemembersItsOwnWebApp() throws {
        let growlrrr = try makeApp(named: "T3 Code (Growlrrr)", webAppStartURL: "https://app.t3.codes/")
        let method = T3CodeReactivation()

        method.promptSubmitted(in: context(threadId: "thread-in-growlrrr", frontmostApp: growlrrr))

        XCTAssertTrue(
            method.clickCommand(in: context(threadId: "thread-in-growlrrr"))?.hasPrefix("open -a ") ?? false)
        XCTAssertEqual(method.clickCommand(in: context(threadId: "another-thread")), desktopCommand)
    }

    func testAPromptFromTheDesktopAppClearsTheRememberedWebApp() throws {
        let webApp = try makeApp(named: "T3 Code (Growlrrr)", webAppStartURL: "https://app.t3.codes/")
        _ = try makeApp(named: "T3 Code (Beta)")
        let method = T3CodeReactivation()

        method.promptSubmitted(in: context(frontmostApp: webApp))
        method.promptSubmitted(in: context(frontmostApp: desktopApp))

        XCTAssertEqual(method.clickCommand(in: context()), desktopCommand)
    }

    func testAPromptWhileAnUnrelatedAppIsFrontmostChangesNothing() throws {
        // A queued or scheduled prompt: nobody typed it into the app in front.
        let webApp = try makeApp(named: "T3 Code (Growlrrr)", webAppStartURL: "https://app.t3.codes/")
        let finder = try makeApp(named: "Finder")
        let whatsApp = try makeApp(named: "WhatsApp Web", webAppStartURL: "https://web.whatsapp.com/")
        let method = T3CodeReactivation()

        method.promptSubmitted(in: context(frontmostApp: webApp))
        method.promptSubmitted(in: context(frontmostApp: finder))
        method.promptSubmitted(in: context(frontmostApp: whatsApp))
        method.promptSubmitted(in: context(frontmostApp: nil))

        XCTAssertTrue(method.clickCommand(in: context())?.hasPrefix("open -a '\(webApp.path)'") ?? false)
    }

    func testAWebAppOfAnotherSiteIsNeverRemembered() throws {
        let whatsApp = try makeApp(named: "WhatsApp Web", webAppStartURL: "https://web.whatsapp.com/")
        let method = T3CodeReactivation()

        method.promptSubmitted(in: context(frontmostApp: whatsApp))

        XCTAssertEqual(method.clickCommand(in: context()), desktopCommand)
    }

    func testARememberedWebAppThatHasBeenDeletedIsIgnored() throws {
        let webApp = try makeApp(named: "T3 Code (Growlrrr)", webAppStartURL: "https://app.t3.codes/")
        let method = T3CodeReactivation()
        method.promptSubmitted(in: context(frontmostApp: webApp))

        try FileManager.default.removeItem(at: webApp)

        XCTAssertEqual(method.clickCommand(in: context()), desktopCommand)
    }

    func testThePromptHookOnlyLooksTheThreadUpWhenItMightRememberSomething() throws {
        // `hook dismiss` runs on every prompt; the CLI lookup must not.
        let webApp = try makeApp(named: "T3 Code (Growlrrr)", webAppStartURL: "https://app.t3.codes/")
        let finder = try makeApp(named: "Finder")
        _ = try makeApp(named: "T3 Code (Beta)")
        let method = T3CodeReactivation()

        method.promptSubmitted(in: context(frontmostApp: finder))
        method.promptSubmitted(in: context(frontmostApp: desktopApp))
        method.promptSubmitted(in: context(frontmostApp: nil))
        XCTAssertEqual(commandsRun.count, 0)

        method.promptSubmitted(in: context(frontmostApp: webApp))
        XCTAssertEqual(commandsRun.count, 1)

        // Already remembered: nothing to learn.
        method.promptSubmitted(in: context(frontmostApp: webApp))
        XCTAssertEqual(commandsRun.count, 1)
    }
}
