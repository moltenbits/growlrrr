import XCTest
import GrowlrrrCore

final class T3CodeAdapterTests: XCTestCase {

    private let threadId = "962887c7-9d48-4440-99bd-0461933b8033"
    private let desktopCommand =
        "open 't3code://threads/7e9a75d0-3c28-48ef-a9f3-9551e82938b6/962887c7-9d48-4440-99bd-0461933b8033'"

    private var scratch: URL!
    /// `t3` CLI invocations, as [executable, arguments..., "timeout=<seconds>"].
    private var commandsRun: [[String]] = []
    /// What the `t3` CLI prints; nil makes it fail.
    private var threadLink: String? =
        "https://app.t3.codes/threads/7e9a75d0-3c28-48ef-a9f3-9551e82938b6/962887c7-9d48-4440-99bd-0461933b8033"
    /// The title the `t3` CLI reports for the thread.
    private var threadTitle: String? = "Clean Up Branches Merged to Main"

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
    ) -> AdapterContext {
        var environment = environment
        environment["T3CODE_THREAD_ID"] = threadId ?? self.threadId
        var context = AdapterContext(
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
                var thread: [String: Any] = ["link": link]
                thread["title"] = self.threadTitle
                let json: [String: Any] = ["thread": thread, "messages": []]
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

    private func codexContext(session: String? = "codex-session", frontmostApp: URL? = nil) -> AdapterContext {
        context(threadId: "", environment: [
            "T3CODE_CLI_PATH": "/Users/me/.t3/bin/t3", "T3CODE_HOME": scratch.path,
        ], frontmostApp: frontmostApp, hookSessionId: session)
    }

    func testCodexHookFindsItsExactThreadAndRemembersThePromptingWebApp() throws {
        try makeT3Database()
        try addCodexSession("other-session", thread: "other-thread")
        try addCodexSession("codex-session", thread: threadId)
        let webApp = try makeApp(named: "T3 Code (Growlrrr)", webAppStartURL: "https://app.t3.codes/")
        let adapters = ApplicationAdapters(adapters: [T3CodeAdapter()])

        adapters.promptSubmitted(in: codexContext(frontmostApp: webApp))

        XCTAssertTrue(adapters.shouldNotify(in: codexContext()))
        XCTAssertEqual(adapters.clickCommand(in: codexContext()),
            "open -a '\(webApp.path)' 'https://app.t3.codes/threads/7e9a75d0-3c28-48ef-a9f3-9551e82938b6/\(threadId)'")
        XCTAssertTrue(commandsRun.contains { $0.contains("show") && $0.contains(threadId) })
        XCTAssertFalse(commandsRun.contains { $0.contains("show") && $0.contains("other-thread") })
    }

    func testT3TitleGenerationWithoutAnAppThreadDoesNotNotify() throws {
        try makeT3Database()
        try addCodexSession("real-session", thread: threadId)
        let adapters = ApplicationAdapters(adapters: [T3CodeAdapter()])

        XCTAssertFalse(adapters.shouldNotify(in: codexContext(session: "ephemeral-title-session")))
        XCTAssertNil(adapters.clickCommand(in: codexContext(session: "ephemeral-title-session")))
    }

    func testUnreadableT3StatePreservesTheNotificationButLeavesTheClickWithoutAnAction() throws {
        let adapters = ApplicationAdapters(adapters: [T3CodeAdapter()])
        XCTAssertTrue(adapters.shouldNotify(in: codexContext()))
        XCTAssertNil(adapters.clickCommand(in: codexContext()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: t3Database.path), "Lookup must not create a database")

        try FileManager.default.createDirectory(at: t3Database.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("not a sqlite database".utf8).write(to: t3Database)
        XCTAssertTrue(adapters.shouldNotify(in: codexContext()))
        XCTAssertNil(adapters.clickCommand(in: codexContext()))
    }

    func testAmbiguousCodexSessionNeverChoosesAnArbitraryThread() throws {
        try makeT3Database()
        try addCodexSession("codex-session", thread: threadId)
        try addCodexSession("codex-session", thread: "another-thread")
        let adapters = ApplicationAdapters(adapters: [T3CodeAdapter()])

        XCTAssertTrue(adapters.shouldNotify(in: codexContext()))
        XCTAssertNil(adapters.clickCommand(in: codexContext()))
    }

    func testCodexSessionLookupDoesNotMatchAnotherProviderOrInterpretSQL() throws {
        try makeT3Database()
        try addCodexSession("codex-session", thread: "claude-thread", provider: "claudeAgent")
        let adapters = ApplicationAdapters(adapters: [T3CodeAdapter()])

        XCTAssertNil(adapters.clickCommand(in: codexContext()))
        XCTAssertNil(adapters.clickCommand(in: codexContext(session: "' OR 1=1 --")))
    }

    func testAnExplicitThreadTakesPrecedenceOverTheCodexSession() {
        let context = context(hookSessionId: "codex-session")
        let adapters = ApplicationAdapters(adapters: [T3CodeAdapter()])

        XCTAssertTrue(adapters.shouldNotify(in: context))
        XCTAssertEqual(adapters.clickCommand(in: context), desktopCommand)
        XCTAssertFalse(commandsRun.contains { $0.first == "/usr/bin/sqlite3" })
    }

    func testNotificationsWithoutAHookSessionAreNotSuppressed() {
        let adapters = ApplicationAdapters(adapters: [T3CodeAdapter()])
        XCTAssertTrue(adapters.shouldNotify(in: codexContext(session: nil)))
        XCTAssertTrue(adapters.shouldNotify(in: AdapterContext(stateDirectory: scratch)))
    }

    // MARK: - Recognising a T3 Code thread

    func testAppliesToAnAgentRunningInAT3CodeThread() {
        let adapter = T3CodeAdapter()
        let anywhere = AdapterContext(stateDirectory: scratch)
        let emptyThreadId = AdapterContext(
            environment: ["T3CODE_THREAD_ID": ""], stateDirectory: scratch)

        XCTAssertTrue(adapter.applies(in: context()))
        XCTAssertFalse(adapter.applies(in: anywhere))
        XCTAssertFalse(adapter.applies(in: emptyThreadId))
    }

    func testIsDiscoveredAsAnAgentAdapter() {
        let discovered = ApplicationAdapters.discover().map { String(describing: type(of: $0)) }

        XCTAssertTrue(discovered.contains("T3CodeAdapter"), "discovered: \(discovered.sorted())")
        XCTAssertEqual(T3CodeAdapter.layer, .agentApp)
    }

    func testWinsOverTheTerminalTheT3ServerWasStartedFrom() {
        // `t3` run in an iTerm2 tab: agents inherit iTerm2's variables too.
        var environment = ["T3CODE_CLI_PATH": "/Users/me/.t3/bin/t3"]
        environment["TERM_PROGRAM"] = "iTerm.app"
        environment["ITERM_SESSION_ID"] = "w0t0p0:15D2E73B-2807-4ED8-8DA2-19AEC7D862B0"
        var warnings: [String] = []
        let adapters = ApplicationAdapters(
            adapters: [ITermAdapter(), T3CodeAdapter()], warn: { warnings.append($0) })

        XCTAssertEqual(adapters.clickCommand(in: context(environment: environment)), desktopCommand)
        XCTAssertEqual(warnings, [])
    }

    // MARK: - The click command

    func testOpensTheThreadInTheDesktopAppByDefault() {
        XCTAssertEqual(T3CodeAdapter().clickCommand(in: context()), desktopCommand)
    }

    func testLooksTheThreadUpWithT3CodesOwnCLIUnderATimeout() {
        _ = T3CodeAdapter().clickCommand(in: context())

        XCTAssertEqual(commandsRun, [[
            "/Users/me/.t3/bin/t3", "thread", "show", threadId, "--json", "--messages", "0", "timeout=5.0",
        ]])
    }

    func testLooksTheThreadUpWithT3OnThePathWhenNoCLIIsNamed() {
        _ = T3CodeAdapter().clickCommand(in: context(environment: [:]))

        XCTAssertEqual(commandsRun, [[
            "/usr/bin/env", "t3", "thread", "show", threadId, "--json", "--messages", "0", "timeout=5.0",
        ]])
    }

    func testAClickDoesNothingWhenTheThreadCannotBeLookedUp() {
        threadLink = nil
        XCTAssertNil(T3CodeAdapter().clickCommand(in: context()))

        threadLink = "https://app.t3.codes/new"
        XCTAssertNil(T3CodeAdapter().clickCommand(in: context()))
    }

    func testAnUnresolvedThreadDoesNotFallBackToActivatingTheParentApp() {
        threadLink = nil
        let underT3Code = AdapterContext(
            environment: ["T3CODE_THREAD_ID": threadId],
            stateDirectory: scratch,
            parentApp: { self.desktopApp })

        XCTAssertNil(ApplicationAdapters(adapters: [T3CodeAdapter()]).clickCommand(in: underT3Code))
    }

    func testAT3CodeHookWithoutAThreadDoesNotActivateTheDesktopAppOrInheritedTerminal() {
        let underT3Code = AdapterContext(
            environment: ["T3CODE_CLI_PATH": "/Users/me/.t3/bin/t3", "TERM_PROGRAM": "iTerm.app"],
            stateDirectory: scratch,
            parentApp: { self.desktopApp })

        XCTAssertTrue(T3CodeAdapter().applies(in: underT3Code))
        XCTAssertNil(ApplicationAdapters(adapters: [T3CodeAdapter(), ITermAdapter()])
            .clickCommand(in: underT3Code))
    }

    // MARK: - Remembering the web app a prompt came from

    func testOpensTheThreadInTheWebAppItWasPromptedFrom() throws {
        let webApp = try makeApp(named: "T3 Code (Growlrrr)", webAppStartURL: "https://app.t3.codes/")
        let adapter = T3CodeAdapter()

        adapter.promptSubmitted(in: context(frontmostApp: webApp))

        XCTAssertEqual(
            adapter.clickCommand(in: context()),
            "open -a '\(webApp.path)' 'https://app.t3.codes/threads/7e9a75d0-3c28-48ef-a9f3-9551e82938b6/962887c7-9d48-4440-99bd-0461933b8033'")
    }

    func testAPromptFromAnotherWebAppReplacesTheRememberedOne() throws {
        let growlrrr = try makeApp(named: "T3 Code (Growlrrr)", webAppStartURL: "https://app.t3.codes/")
        let listenly = try makeApp(named: "T3 Code (Listenly)", webAppStartURL: "https://app.t3.codes/")
        let adapter = T3CodeAdapter()

        adapter.promptSubmitted(in: context(frontmostApp: growlrrr))
        adapter.promptSubmitted(in: context(frontmostApp: listenly))

        XCTAssertTrue(adapter.clickCommand(in: context())?.hasPrefix("open -a '\(listenly.path)'") ?? false)
    }

    func testEachThreadRemembersItsOwnWebApp() throws {
        let growlrrr = try makeApp(named: "T3 Code (Growlrrr)", webAppStartURL: "https://app.t3.codes/")
        let adapter = T3CodeAdapter()

        adapter.promptSubmitted(in: context(threadId: "thread-in-growlrrr", frontmostApp: growlrrr))

        XCTAssertTrue(
            adapter.clickCommand(in: context(threadId: "thread-in-growlrrr"))?.hasPrefix("open -a ") ?? false)
        XCTAssertEqual(adapter.clickCommand(in: context(threadId: "another-thread")), desktopCommand)
    }

    func testAPromptFromTheDesktopAppClearsTheRememberedWebApp() throws {
        let webApp = try makeApp(named: "T3 Code (Growlrrr)", webAppStartURL: "https://app.t3.codes/")
        _ = try makeApp(named: "T3 Code (Beta)")
        let adapter = T3CodeAdapter()

        adapter.promptSubmitted(in: context(frontmostApp: webApp))
        adapter.promptSubmitted(in: context(frontmostApp: desktopApp))

        XCTAssertEqual(adapter.clickCommand(in: context()), desktopCommand)
    }

    func testAPromptWhileAnUnrelatedAppIsFrontmostChangesNothing() throws {
        // A queued or scheduled prompt: nobody typed it into the app in front.
        let webApp = try makeApp(named: "T3 Code (Growlrrr)", webAppStartURL: "https://app.t3.codes/")
        let finder = try makeApp(named: "Finder")
        let whatsApp = try makeApp(named: "WhatsApp Web", webAppStartURL: "https://web.whatsapp.com/")
        let adapter = T3CodeAdapter()

        adapter.promptSubmitted(in: context(frontmostApp: webApp))
        adapter.promptSubmitted(in: context(frontmostApp: finder))
        adapter.promptSubmitted(in: context(frontmostApp: whatsApp))
        adapter.promptSubmitted(in: context(frontmostApp: nil))

        XCTAssertTrue(adapter.clickCommand(in: context())?.hasPrefix("open -a '\(webApp.path)'") ?? false)
    }

    func testAWebAppOfAnotherSiteIsNeverRemembered() throws {
        let whatsApp = try makeApp(named: "WhatsApp Web", webAppStartURL: "https://web.whatsapp.com/")
        let adapter = T3CodeAdapter()

        adapter.promptSubmitted(in: context(frontmostApp: whatsApp))

        XCTAssertEqual(adapter.clickCommand(in: context()), desktopCommand)
    }

    func testARememberedWebAppThatHasBeenDeletedIsIgnored() throws {
        let webApp = try makeApp(named: "T3 Code (Growlrrr)", webAppStartURL: "https://app.t3.codes/")
        let adapter = T3CodeAdapter()
        adapter.promptSubmitted(in: context(frontmostApp: webApp))

        try FileManager.default.removeItem(at: webApp)

        XCTAssertEqual(adapter.clickCommand(in: context()), desktopCommand)
    }

    func testThePromptHookOnlyLooksTheThreadUpWhenItMightRememberSomething() throws {
        // `hook dismiss` runs on every prompt; the CLI lookup must not.
        let webApp = try makeApp(named: "T3 Code (Growlrrr)", webAppStartURL: "https://app.t3.codes/")
        let finder = try makeApp(named: "Finder")
        _ = try makeApp(named: "T3 Code (Beta)")
        let adapter = T3CodeAdapter()

        adapter.promptSubmitted(in: context(frontmostApp: finder))
        adapter.promptSubmitted(in: context(frontmostApp: desktopApp))
        adapter.promptSubmitted(in: context(frontmostApp: nil))
        XCTAssertEqual(commandsRun.count, 0)

        adapter.promptSubmitted(in: context(frontmostApp: webApp))
        XCTAssertEqual(commandsRun.count, 1)

        // Already remembered: nothing to learn.
        adapter.promptSubmitted(in: context(frontmostApp: webApp))
        XCTAssertEqual(commandsRun.count, 1)
    }

    // MARK: - The conversation name

    func testTheConversationIsNamedAfterTheThreadTitle() {
        XCTAssertEqual(T3CodeAdapter().conversationName(in: context()), "Clean Up Branches Merged to Main")
    }

    func testACodexHookNamesTheThreadItsSessionBelongsTo() throws {
        try makeT3Database()
        try addCodexSession("codex-session", thread: threadId)

        XCTAssertEqual(
            ApplicationAdapters(adapters: [T3CodeAdapter()]).conversationName(in: codexContext()),
            "Clean Up Branches Merged to Main")
    }

    func testTheConversationIsUnnamedWhenTheThreadHasNoTitleOrCannotBeLookedUp() {
        threadTitle = nil
        XCTAssertNil(T3CodeAdapter().conversationName(in: context()))

        threadTitle = "Clean Up Branches Merged to Main"
        threadLink = nil
        XCTAssertNil(T3CodeAdapter().conversationName(in: context()))
    }

    func testTheClickAndTheNameShareOneThreadLookup() {
        let adapter = T3CodeAdapter()

        XCTAssertEqual(adapter.clickCommand(in: context()), desktopCommand)
        XCTAssertEqual(adapter.conversationName(in: context()), "Clean Up Branches Merged to Main")

        XCTAssertEqual(commandsRun.count, 1, "\(commandsRun)")
    }

    func testAFailedThreadLookupIsNotRepeatedForTheName() {
        // A lookup that fails may have waited out its timeout.
        threadLink = nil
        let adapter = T3CodeAdapter()

        XCTAssertNil(adapter.clickCommand(in: context()))
        XCTAssertNil(adapter.conversationName(in: context()))

        XCTAssertEqual(commandsRun.count, 1, "\(commandsRun)")
    }
}
