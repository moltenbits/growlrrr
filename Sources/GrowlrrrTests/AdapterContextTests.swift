import XCTest
import GrowlrrrCore

private final class StoreOwner: ApplicationAdapter {
    init() {}
    func applies(in context: AdapterContext) -> Bool { false }
    func clickCommand(in context: AdapterContext) -> String? { nil }
}

private final class OtherStoreOwner: ApplicationAdapter {
    init() {}
    func applies(in context: AdapterContext) -> Bool { false }
    func clickCommand(in context: AdapterContext) -> String? { nil }
}

final class AdapterContextTests: XCTestCase {

    private var stateDirectory: URL!

    override func setUpWithError() throws {
        // Deliberately not created: a store makes its directory on first write.
        stateDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("growlrrr-adapters-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: stateDirectory)
    }

    private func context(
        run: @escaping AdapterContext.CommandRunner = { _, _, _ in nil }
    ) -> AdapterContext {
        AdapterContext(stateDirectory: stateDirectory, run: run)
    }

    // MARK: - Shell quoting

    func testShellQuotedWrapsAValueInSingleQuotes() {
        XCTAssertEqual(
            AdapterContext.shellQuoted("/Applications/T3 Code (Beta).app"),
            "'/Applications/T3 Code (Beta).app'")
    }

    func testShellQuotedEscapesAnApostrophe() {
        XCTAssertEqual(
            AdapterContext.shellQuoted("/Applications/Sam's App.app"),
            #"'/Applications/Sam'\''s App.app'"#)
    }

    // MARK: - AppleScript

    func testAppleScriptRunsOsascriptAndTrimsItsOutput() {
        var calls: [[String]] = []
        let context = context(run: { executable, arguments, _ in
            calls.append([executable] + arguments)
            return Data("  12345, 2\n".utf8)
        })

        XCTAssertEqual(context.appleScript("tell application \"Terminal\" to id of front window"), "12345, 2")
        XCTAssertEqual(calls, [["/usr/bin/osascript", "-e", "tell application \"Terminal\" to id of front window"]])
    }

    func testAppleScriptHasNoResultWhenTheScriptFailsOrPrintsNothing() {
        XCTAssertNil(context(run: { _, _, _ in nil }).appleScript("anything"))
        XCTAssertNil(context(run: { _, _, _ in Data("\n".utf8) }).appleScript("anything"))
    }

    // MARK: - Running commands for real

    func testLiveContextReturnsACommandsOutput() {
        let output = AdapterContext.live().run("/bin/echo", ["hello"])
        XCTAssertEqual(output.map { String(decoding: $0, as: UTF8.self) }, "hello\n")
    }

    func testLiveContextHasNoOutputForACommandThatFails() {
        XCTAssertNil(AdapterContext.live().run("/usr/bin/false", []))
        XCTAssertNil(AdapterContext.live().run("/nonexistent/command", []))
    }

    func testLiveContextGivesUpOnACommandThatOutlastsItsTimeout() {
        let started = Date()
        XCTAssertNil(AdapterContext.live().run("/bin/sleep", ["10"], timeout: 0.2))
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    func testLiveContextReadsOutputLargerThanAPipeBuffer() {
        // 200 kB is more than a pipe holds; the command would block forever
        // if its output were only read after it exited.
        let output = AdapterContext.live().run(
            "/bin/sh", ["-c", "head -c 200000 /dev/zero"], timeout: 10)
        XCTAssertEqual(output?.count, 200_000)
    }

    // MARK: - Per-adapter store

    func testAStoreWithNothingRememberedHasNoValue() {
        XCTAssertNil(context().store(for: StoreOwner()).value(forKey: "thread-1"))
    }

    func testAStoreRemembersValuesByKey() throws {
        let store = context().store(for: StoreOwner())
        try store.set("/Users/me/Applications/T3 Code (Growlrrr).app", forKey: "thread-1")
        try store.set("/Users/me/Applications/T3 Code (Listenly).app", forKey: "thread-2")

        XCTAssertEqual(store.value(forKey: "thread-1"), "/Users/me/Applications/T3 Code (Growlrrr).app")
        XCTAssertEqual(store.value(forKey: "thread-2"), "/Users/me/Applications/T3 Code (Listenly).app")
    }

    func testSettingAKeyAgainReplacesItsValue() throws {
        let store = context().store(for: StoreOwner())
        try store.set("first", forKey: "thread-1")
        try store.set("second", forKey: "thread-1")

        XCTAssertEqual(store.value(forKey: "thread-1"), "second")
    }

    func testAnotherContextOnTheSameDirectorySeesWhatWasStored() throws {
        // `hook dismiss` writes and `hook notify` reads in separate processes.
        try context().store(for: StoreOwner()).set("remembered", forKey: "thread-1")

        XCTAssertEqual(context().store(for: StoreOwner()).value(forKey: "thread-1"), "remembered")
    }

    func testEachAdapterHasItsOwnStore() throws {
        try context().store(for: StoreOwner()).set("mine", forKey: "thread-1")

        XCTAssertNil(context().store(for: OtherStoreOwner()).value(forKey: "thread-1"))
    }

    func testRemovingAKeyForgetsItsValue() throws {
        let store = context().store(for: StoreOwner())
        try store.set("remembered", forKey: "thread-1")
        store.removeValue(forKey: "thread-1")
        store.removeValue(forKey: "never-set")

        XCTAssertNil(store.value(forKey: "thread-1"))
    }

    func testAStoreRefusesKeysThatAreNotPlainNames() throws {
        // A key becomes a file name inside the store's directory.
        let store = context().store(for: StoreOwner())

        XCTAssertThrowsError(try store.set("value", forKey: "../escaped"))
        XCTAssertThrowsError(try store.set("value", forKey: ""))
        XCTAssertNil(store.value(forKey: "../escaped"))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: stateDirectory.appendingPathComponent("escaped").path))
    }
}
