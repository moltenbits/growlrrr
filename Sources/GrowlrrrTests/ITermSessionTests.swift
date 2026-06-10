import XCTest
import GrowlrrrCore

final class ITermSessionTests: XCTestCase {

    func testRevealCommandPreservesFullSessionId() {
        // iTerm's revealSessionID: strips the wXtXpX: prefix itself, so the
        // full ITERM_SESSION_ID value must be passed through unstripped.
        let command = ITermSession.revealCommand(
            sessionId: "w2t0p0:15D2E73B-2807-4ED8-8DA2-19AEC7D862B0")
        XCTAssertEqual(
            command,
            "open 'iterm2:reveal?sessionid=w2t0p0:15D2E73B-2807-4ED8-8DA2-19AEC7D862B0'")
    }

    func testRevealCommandUsesOpaqueURLForm() {
        // iTerm matches the URL path against the literal "reveal", so the
        // slashed form (iterm2:///reveal, path "/reveal") is never handled.
        let command = ITermSession.revealCommand(sessionId: "w0t0p0:ABC-123")
        XCTAssertNotNil(command)
        XCTAssertTrue(command!.contains("iterm2:reveal?"))
        XCTAssertFalse(command!.contains("iterm2://"))
    }

    func testRevealCommandRejectsEmptySessionId() {
        XCTAssertNil(ITermSession.revealCommand(sessionId: ""))
    }

    func testRevealCommandRejectsSessionIdWithoutColon() {
        // A bare GUID has no colon; iTerm takes the substring after the first
        // colon, so revealing a colonless value is a silent no-op.
        XCTAssertNil(
            ITermSession.revealCommand(sessionId: "15D2E73B-2807-4ED8-8DA2-19AEC7D862B0"))
    }

    func testRevealCommandRejectsUnexpectedCharacters() {
        // The command is executed via `sh -c`; anything outside iTerm's
        // wXtXpX:UUID alphabet falls through to the AppleScript strategies.
        XCTAssertNil(ITermSession.revealCommand(sessionId: "w0t0p0:GUID'; rm -rf ~'"))
        XCTAssertNil(ITermSession.revealCommand(sessionId: "w0t0p0:GUID WITH SPACE"))
        XCTAssertNil(ITermSession.revealCommand(sessionId: "w0t0p0:GUID&x=y"))
    }
}
