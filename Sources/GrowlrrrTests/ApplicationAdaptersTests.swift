import XCTest
import GrowlrrrCore

// Adapters for exercising how ApplicationAdapters chooses between them. Each is its
// own class because a tie between two adapters is reported by type name.

private final class TerminalAdapter: ApplicationAdapter {
    var isApplicable = true
    var command: String? = "terminal-command"
    var promptsSeen = 0
    init() {}
    func applies(in context: AdapterContext) -> Bool { isApplicable }
    func clickCommand(in context: AdapterContext) -> String? { command }
    func promptSubmitted(in context: AdapterContext) { promptsSeen += 1 }
}

private final class AnotherTerminalAdapter: ApplicationAdapter {
    var promptsSeen = 0
    init() {}
    func applies(in context: AdapterContext) -> Bool { true }
    func clickCommand(in context: AdapterContext) -> String? { "another-terminal-command" }
    func promptSubmitted(in context: AdapterContext) { promptsSeen += 1 }
}

private final class AgentAppAdapter: ApplicationAdapter {
    static let layer = AdapterLayer.agentApp
    var isApplicable = true
    var command: String? = "agent-adapter-command"
    var promptsSeen = 0
    init() {}
    func applies(in context: AdapterContext) -> Bool { isApplicable }
    func clickCommand(in context: AdapterContext) -> String? { command }
    func promptSubmitted(in context: AdapterContext) { promptsSeen += 1 }
}

/// Implements only what the protocol requires.
private final class MinimalAdapter: ApplicationAdapter {
    init() {}
    func applies(in context: AdapterContext) -> Bool { true }
    func clickCommand(in context: AdapterContext) -> String? { "minimal-command" }
}

final class ApplicationAdaptersTests: XCTestCase {

    private var stateDirectory: URL!
    private var warnings: [String] = []

    override func setUpWithError() throws {
        stateDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("growlrrr-adapters-\(UUID().uuidString)")
        warnings = []
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: stateDirectory)
    }

    private func context(
        environment: [String: String] = [:],
        parentApp: URL? = nil
    ) -> AdapterContext {
        AdapterContext(
            environment: environment, stateDirectory: stateDirectory, parentApp: { parentApp })
    }

    private func applicationAdapters(_ adapters: [ApplicationAdapter]) -> ApplicationAdapters {
        ApplicationAdapters(adapters: adapters, warn: { self.warnings.append($0) })
    }

    // MARK: - One adapter applies

    func testUsesTheCommandOfTheMethodThatApplies() {
        let terminal = TerminalAdapter()
        let agentApp = AgentAppAdapter()
        agentApp.isApplicable = false

        XCTAssertEqual(applicationAdapters([terminal, agentApp]).clickCommand(in: context()), "terminal-command")
        XCTAssertEqual(warnings, [])
    }

    func testAMethodThatAppliesButHasNoCommandLeavesTheClickWithoutAnAction() {
        // The adapter recognised its own adapter and declined to act. That must
        // not fall through to activating the parent app.
        let agentApp = AgentAppAdapter()
        agentApp.command = nil
        let parentApp = URL(fileURLWithPath: "/Applications/Some Editor.app")

        XCTAssertNil(applicationAdapters([agentApp]).clickCommand(in: context(parentApp: parentApp)))
    }

    func testALayerIsATerminalUnlessTheMethodSaysOtherwise() {
        XCTAssertEqual(MinimalAdapter.layer, .terminal)
        XCTAssertEqual(AgentAppAdapter.layer, .agentApp)
    }

    // MARK: - Several adapters apply

    func testTheInnermostLayerWinsWhenMethodsInDifferentLayersApply() {
        // An agent app started from a terminal carries both adapters'
        // variables; the person was working in the agent app.
        let adapters: [ApplicationAdapter] = [TerminalAdapter(), AgentAppAdapter()]

        XCTAssertEqual(applicationAdapters(adapters).clickCommand(in: context()), "agent-adapter-command")
        XCTAssertEqual(applicationAdapters(adapters.reversed()).clickCommand(in: context()), "agent-adapter-command")
        XCTAssertEqual(warnings, [])
    }

    func testATieWithinALayerIsSettledByNameAndReported() {
        let adapters: [ApplicationAdapter] = [TerminalAdapter(), AnotherTerminalAdapter()]

        XCTAssertEqual(applicationAdapters(adapters).clickCommand(in: context()), "another-terminal-command")
        XCTAssertEqual(applicationAdapters(adapters.reversed()).clickCommand(in: context()), "another-terminal-command")
        XCTAssertEqual(warnings.count, 2)
        XCTAssertTrue(warnings[0].contains("AnotherTerminalAdapter"), warnings[0])
        XCTAssertTrue(warnings[0].contains("TerminalAdapter"), warnings[0])
    }

    // MARK: - No adapter applies

    func testActivatesTheParentAppWhenNoMethodApplies() {
        let terminal = TerminalAdapter()
        terminal.isApplicable = false
        let parentApp = URL(fileURLWithPath: "/Applications/Visual Studio Code.app")

        XCTAssertEqual(
            applicationAdapters([terminal]).clickCommand(in: context(parentApp: parentApp)),
            "open -a '/Applications/Visual Studio Code.app'")
    }

    func testFallsBackToTheTerminalProgramNameWhenThereIsNoParentApp() {
        // A shell detached from its terminal still inherits TERM_PROGRAM.
        XCTAssertEqual(
            applicationAdapters([]).clickCommand(in: context(environment: ["TERM_PROGRAM": "WezTerm"])),
            "osascript -e 'tell application \"WezTerm\" to activate'")
    }

    func testIgnoresATerminalProgramNameThatIsNotAPlainName() {
        XCTAssertNil(applicationAdapters([]).clickCommand(
            in: context(environment: ["TERM_PROGRAM": "x\" to quit' ; rm -rf ~ ; '"])))
    }

    func testHasNoCommandWhenNothingIsKnownAboutTheAdapter() {
        XCTAssertNil(applicationAdapters([]).clickCommand(in: context()))
        XCTAssertNil(applicationAdapters([]).clickCommand(in: context(environment: ["TERM_PROGRAM": ""])))
    }

    // MARK: - Prompt submitted

    func testOnlyTheMethodThatWouldHandleTheClickHearsAboutAPrompt() {
        let terminal = TerminalAdapter()
        let agentApp = AgentAppAdapter()

        applicationAdapters([terminal, agentApp]).promptSubmitted(in: context())

        XCTAssertEqual(agentApp.promptsSeen, 1)
        XCTAssertEqual(terminal.promptsSeen, 0)
    }

    func testAPromptWithNoApplicableMethodIsIgnored() {
        let terminal = TerminalAdapter()
        terminal.isApplicable = false

        applicationAdapters([terminal]).promptSubmitted(in: context())

        XCTAssertEqual(terminal.promptsSeen, 0)
    }

    func testAMethodNeedNotCareAboutPrompts() {
        applicationAdapters([MinimalAdapter()]).promptSubmitted(in: context())
    }
}
