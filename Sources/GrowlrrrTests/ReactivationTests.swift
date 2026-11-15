import XCTest
import GrowlrrrCore

// Methods for exercising how Reactivation chooses between them. Each is its
// own class because a tie between two methods is reported by type name.

private final class TerminalMethod: ReactivationMethod {
    var isApplicable = true
    var command: String? = "terminal-command"
    var promptsSeen = 0
    init() {}
    func applies(in context: ReactivationContext) -> Bool { isApplicable }
    func clickCommand(in context: ReactivationContext) -> String? { command }
    func promptSubmitted(in context: ReactivationContext) { promptsSeen += 1 }
}

private final class AnotherTerminalMethod: ReactivationMethod {
    var promptsSeen = 0
    init() {}
    func applies(in context: ReactivationContext) -> Bool { true }
    func clickCommand(in context: ReactivationContext) -> String? { "another-terminal-command" }
    func promptSubmitted(in context: ReactivationContext) { promptsSeen += 1 }
}

private final class AgentHostMethod: ReactivationMethod {
    static let layer = ReactivationLayer.agentHost
    var isApplicable = true
    var command: String? = "agent-host-command"
    var promptsSeen = 0
    init() {}
    func applies(in context: ReactivationContext) -> Bool { isApplicable }
    func clickCommand(in context: ReactivationContext) -> String? { command }
    func promptSubmitted(in context: ReactivationContext) { promptsSeen += 1 }
}

/// Implements only what the protocol requires.
private final class MinimalMethod: ReactivationMethod {
    init() {}
    func applies(in context: ReactivationContext) -> Bool { true }
    func clickCommand(in context: ReactivationContext) -> String? { "minimal-command" }
}

final class ReactivationTests: XCTestCase {

    private var stateDirectory: URL!
    private var warnings: [String] = []

    override func setUpWithError() throws {
        stateDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("growlrrr-reactivation-\(UUID().uuidString)")
        warnings = []
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: stateDirectory)
    }

    private func context(
        environment: [String: String] = [:],
        hostApp: URL? = nil
    ) -> ReactivationContext {
        ReactivationContext(
            environment: environment, stateDirectory: stateDirectory, hostApp: { hostApp })
    }

    private func reactivation(_ methods: [ReactivationMethod]) -> Reactivation {
        Reactivation(methods: methods, warn: { self.warnings.append($0) })
    }

    // MARK: - One method applies

    func testUsesTheCommandOfTheMethodThatApplies() {
        let terminal = TerminalMethod()
        let agentHost = AgentHostMethod()
        agentHost.isApplicable = false

        XCTAssertEqual(reactivation([terminal, agentHost]).clickCommand(in: context()), "terminal-command")
        XCTAssertEqual(warnings, [])
    }

    func testAMethodThatAppliesButHasNoCommandLeavesTheClickWithoutAnAction() {
        // The method recognised its own host and declined to act. That must
        // not fall through to activating the host app.
        let agentHost = AgentHostMethod()
        agentHost.command = nil
        let hostApp = URL(fileURLWithPath: "/Applications/Some Host.app")

        XCTAssertNil(reactivation([agentHost]).clickCommand(in: context(hostApp: hostApp)))
    }

    func testALayerIsATerminalUnlessTheMethodSaysOtherwise() {
        XCTAssertEqual(MinimalMethod.layer, .terminal)
        XCTAssertEqual(AgentHostMethod.layer, .agentHost)
    }

    // MARK: - Several methods apply

    func testTheInnermostLayerWinsWhenMethodsInDifferentLayersApply() {
        // An agent host started from a terminal carries both hosts'
        // variables; the person was working in the agent host.
        let methods: [ReactivationMethod] = [TerminalMethod(), AgentHostMethod()]

        XCTAssertEqual(reactivation(methods).clickCommand(in: context()), "agent-host-command")
        XCTAssertEqual(reactivation(methods.reversed()).clickCommand(in: context()), "agent-host-command")
        XCTAssertEqual(warnings, [])
    }

    func testATieWithinALayerIsSettledByNameAndReported() {
        let methods: [ReactivationMethod] = [TerminalMethod(), AnotherTerminalMethod()]

        XCTAssertEqual(reactivation(methods).clickCommand(in: context()), "another-terminal-command")
        XCTAssertEqual(reactivation(methods.reversed()).clickCommand(in: context()), "another-terminal-command")
        XCTAssertEqual(warnings.count, 2)
        XCTAssertTrue(warnings[0].contains("AnotherTerminalMethod"), warnings[0])
        XCTAssertTrue(warnings[0].contains("TerminalMethod"), warnings[0])
    }

    // MARK: - No method applies

    func testActivatesTheHostAppWhenNoMethodApplies() {
        let terminal = TerminalMethod()
        terminal.isApplicable = false
        let hostApp = URL(fileURLWithPath: "/Applications/Visual Studio Code.app")

        XCTAssertEqual(
            reactivation([terminal]).clickCommand(in: context(hostApp: hostApp)),
            "open -a '/Applications/Visual Studio Code.app'")
    }

    func testFallsBackToTheTerminalProgramNameWhenThereIsNoHostApp() {
        // A shell detached from its terminal still inherits TERM_PROGRAM.
        XCTAssertEqual(
            reactivation([]).clickCommand(in: context(environment: ["TERM_PROGRAM": "WezTerm"])),
            "osascript -e 'tell application \"WezTerm\" to activate'")
    }

    func testIgnoresATerminalProgramNameThatIsNotAPlainName() {
        XCTAssertNil(reactivation([]).clickCommand(
            in: context(environment: ["TERM_PROGRAM": "x\" to quit' ; rm -rf ~ ; '"])))
    }

    func testHasNoCommandWhenNothingIsKnownAboutTheHost() {
        XCTAssertNil(reactivation([]).clickCommand(in: context()))
        XCTAssertNil(reactivation([]).clickCommand(in: context(environment: ["TERM_PROGRAM": ""])))
    }

    // MARK: - Prompt submitted

    func testOnlyTheMethodThatWouldHandleTheClickHearsAboutAPrompt() {
        let terminal = TerminalMethod()
        let agentHost = AgentHostMethod()

        reactivation([terminal, agentHost]).promptSubmitted(in: context())

        XCTAssertEqual(agentHost.promptsSeen, 1)
        XCTAssertEqual(terminal.promptsSeen, 0)
    }

    func testAPromptWithNoApplicableMethodIsIgnored() {
        let terminal = TerminalMethod()
        terminal.isApplicable = false

        reactivation([terminal]).promptSubmitted(in: context())

        XCTAssertEqual(terminal.promptsSeen, 0)
    }

    func testAMethodNeedNotCareAboutPrompts() {
        reactivation([MinimalMethod()]).promptSubmitted(in: context())
    }
}
