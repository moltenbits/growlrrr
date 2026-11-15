import XCTest
import GrowlrrrCore

/// The adapters that are terminals: iTerm2, Terminal.app, Ghostty,
/// and the terminals that are only activated by name.
final class TerminalAdapterTests: XCTestCase {

    /// AppleScripts the adapter under test ran, in order.
    private var scriptsRun: [String] = []

    override func setUp() {
        scriptsRun = []
    }

    /// A context whose AppleScripts print `scriptOutput` (nil: they fail).
    private func context(
        environment: [String: String],
        tty: String? = nil,
        scriptOutput: String? = nil
    ) -> AdapterContext {
        AdapterContext(
            environment: environment,
            tty: tty,
            stateDirectory: FileManager.default.temporaryDirectory,
            run: { executable, arguments, _ in
                XCTAssertEqual(executable, "/usr/bin/osascript")
                XCTAssertEqual(arguments.first, "-e")
                self.scriptsRun.append(arguments.last ?? "")
                return scriptOutput.map { Data($0.utf8) }
            })
    }

    // MARK: - Discovery

    func testTheTerminalMethodsAreDiscovered() {
        let discovered = Set(ApplicationAdapters.discover().map { String(describing: type(of: $0)) })

        XCTAssertTrue(
            discovered.isSuperset(of: [
                "ITermAdapter", "TerminalAppAdapter", "GhosttyAdapter",
                "NamedTerminalAdapter",
            ]),
            "discovered: \(discovered.sorted())")
    }

    func testTerminalMethodsSitInTheTerminalLayer() {
        XCTAssertEqual(ITermAdapter.layer, .terminal)
        XCTAssertEqual(TerminalAppAdapter.layer, .terminal)
        XCTAssertEqual(GhosttyAdapter.layer, .terminal)
        XCTAssertEqual(NamedTerminalAdapter.layer, .terminal)
    }

    func testAtMostOneTerminalMethodAppliesToATerminal() {
        let adapters: [ApplicationAdapter] = [
            ITermAdapter(), TerminalAppAdapter(), GhosttyAdapter(),
            NamedTerminalAdapter(),
        ]
        let expected = [
            "iTerm.app": "ITermAdapter",
            "Apple_Terminal": "TerminalAppAdapter",
            "ghostty": "GhosttyAdapter",
            "WarpTerminal": "NamedTerminalAdapter",
            "Alacritty": "NamedTerminalAdapter",
            "kitty": "NamedTerminalAdapter",
        ]
        for (termProgram, adapterName) in expected {
            let applicable = adapters
                .filter { $0.applies(in: context(environment: ["TERM_PROGRAM": termProgram])) }
                .map { String(describing: type(of: $0)) }
            XCTAssertEqual(applicable, [adapterName], termProgram)
        }
        for unknown in [[:], ["TERM_PROGRAM": "vscode"], ["TERM_PROGRAM": ""]] {
            XCTAssertTrue(adapters.allSatisfy { !$0.applies(in: context(environment: unknown)) })
        }
    }

    // MARK: - iTerm2

    func testITermRevealsTheSessionNamedInTheEnvironment() {
        let command = ITermAdapter().clickCommand(in: context(environment: [
            "TERM_PROGRAM": "iTerm.app",
            "ITERM_SESSION_ID": "w2t0p0:15D2E73B-2807-4ED8-8DA2-19AEC7D862B0",
        ]))

        XCTAssertEqual(command, "open 'iterm2:reveal?sessionid=w2t0p0:15D2E73B-2807-4ED8-8DA2-19AEC7D862B0'")
        XCTAssertEqual(scriptsRun, [])
    }

    func testITermFindsTheSessionByTtyWithoutASessionId() {
        let command = ITermAdapter().clickCommand(in: context(
            environment: ["TERM_PROGRAM": "iTerm.app"], tty: "/dev/ttys004"))

        XCTAssertEqual(command, """
            osascript <<'APPLESCRIPT'
            tell application "iTerm2"
                activate
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "/dev/ttys004" then
                                select w
                                select t
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            APPLESCRIPT
            """)
        XCTAssertEqual(scriptsRun, [])
    }

    func testITermIgnoresASessionIdItCannotReveal() {
        // A bare GUID has no wXtXpX: prefix, so the reveal URL would be a
        // silent no-op; fall through to the tty.
        let command = ITermAdapter().clickCommand(in: context(
            environment: [
                "TERM_PROGRAM": "iTerm.app",
                "ITERM_SESSION_ID": "15D2E73B-2807-4ED8-8DA2-19AEC7D862B0",
            ],
            tty: "/dev/ttys004"))

        XCTAssertTrue(command?.contains(#"tty of s is "/dev/ttys004""#) ?? false)
    }

    func testITermAsksForTheCurrentSessionWithoutASessionIdOrTty() {
        let command = ITermAdapter().clickCommand(in: context(
            environment: ["TERM_PROGRAM": "iTerm.app"],
            scriptOutput: "15D2E73B-2807-4ED8-8DA2-19AEC7D862B0\n"))

        XCTAssertEqual(scriptsRun, ["tell application \"iTerm2\" to id of current session of current window"])
        XCTAssertEqual(command, """
            osascript <<'APPLESCRIPT'
            tell application "iTerm2"
                activate
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if id of s is "15D2E73B-2807-4ED8-8DA2-19AEC7D862B0" then
                                select w
                                select t
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            APPLESCRIPT
            """)
    }

    func testITermOnlyActivatesWhenTheCurrentSessionIsUnknown() {
        let command = ITermAdapter().clickCommand(in: context(
            environment: ["TERM_PROGRAM": "iTerm.app"], scriptOutput: nil))

        XCTAssertEqual(command, "osascript -e 'tell application \"iTerm2\" to activate'")
    }

    // MARK: - Terminal.app

    func testTerminalAppReturnsToTheFrontWindowAndTabAtSendTime() {
        let command = TerminalAppAdapter().clickCommand(in: context(
            environment: ["TERM_PROGRAM": "Apple_Terminal"], scriptOutput: "12345,2\n"))

        XCTAssertEqual(scriptsRun.count, 1)
        XCTAssertTrue(scriptsRun[0].contains("id of front window"))
        XCTAssertEqual(command, """
            osascript <<'APPLESCRIPT'
            tell application "Terminal"
                repeat with w in windows
                    if id of w is 12345 then
                        set selected tab of w to tab 2 of w
                        set frontmost of w to true
                        activate
                        return
                    end if
                end repeat
            end tell
            APPLESCRIPT
            """)
    }

    func testTerminalAppOnlyActivatesWhenTheWindowIsUnknown() {
        let activate = "osascript -e 'tell application \"Terminal\" to activate'"
        let environment = ["TERM_PROGRAM": "Apple_Terminal"]

        XCTAssertEqual(
            TerminalAppAdapter().clickCommand(in: context(environment: environment, scriptOutput: nil)),
            activate)
        XCTAssertEqual(
            TerminalAppAdapter().clickCommand(in: context(environment: environment, scriptOutput: "12345")),
            activate)
        XCTAssertEqual(
            TerminalAppAdapter().clickCommand(
                in: context(environment: environment, scriptOutput: "front, window")),
            activate)
    }

    // MARK: - Ghostty

    func testGhosttyReturnsToTheFocusedTerminalAtSendTime() {
        let command = GhosttyAdapter().clickCommand(in: context(
            environment: ["TERM_PROGRAM": "ghostty"], scriptOutput: "8C1D5B6E-0F2A-4C3D-9E7F-1A2B3C4D5E6F\n"))

        XCTAssertEqual(scriptsRun.count, 1)
        XCTAssertTrue(scriptsRun[0].contains("focused terminal of selected tab of front window"))
        XCTAssertEqual(command, """
            osascript <<'APPLESCRIPT'
            tell application "Ghostty"
                activate
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with term in terminals of t
                            if id of term is "8C1D5B6E-0F2A-4C3D-9E7F-1A2B3C4D5E6F" then
                                focus term
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            APPLESCRIPT
            """)
    }

    func testGhosttyOnlyActivatesWhenTheTerminalIsUnknown() {
        let command = GhosttyAdapter().clickCommand(in: context(
            environment: ["TERM_PROGRAM": "ghostty"], scriptOutput: nil))

        XCTAssertEqual(command, "osascript -e 'tell application \"Ghostty\" to activate'")
    }

    // MARK: - Terminals activated by name

    func testNamedTerminalsAreActivatedByAppName() {
        let appNames = ["WarpTerminal": "Warp", "Alacritty": "Alacritty", "kitty": "kitty"]
        for (termProgram, appName) in appNames {
            XCTAssertEqual(
                NamedTerminalAdapter().clickCommand(in: context(environment: ["TERM_PROGRAM": termProgram])),
                "osascript -e 'tell application \"\(appName)\" to activate'")
        }
        XCTAssertEqual(scriptsRun, [])
    }
}
