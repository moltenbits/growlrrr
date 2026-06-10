import XCTest
import GrowlrrrCore

final class HookSessionTests: XCTestCase {

    func testDerivePrefersEnvironmentSessionId() {
        // Shell hooks autoclear "growlrrr-hook-$GROWLRRR_SESSION_ID", so the
        // env var must win when present.
        let sessionId = HookSession.derive(
            environmentSessionId: "12345",
            stdinSessionId: "claude-session-abc",
            appId: "MyApp")
        XCTAssertEqual(sessionId, "12345")
    }

    func testDeriveFallsBackToStdinSessionId() {
        let sessionId = HookSession.derive(
            environmentSessionId: nil,
            stdinSessionId: "claude-session-abc",
            appId: "MyApp")
        XCTAssertEqual(sessionId, "claude-session-abc")
    }

    func testDeriveFallsBackToAppId() {
        let sessionId = HookSession.derive(
            environmentSessionId: nil,
            stdinSessionId: nil,
            appId: "MyApp")
        XCTAssertEqual(sessionId, "MyApp")
    }

    func testDeriveDefaultsWhenNothingAvailable() {
        let sessionId = HookSession.derive(
            environmentSessionId: nil,
            stdinSessionId: nil,
            appId: nil)
        XCTAssertEqual(sessionId, "default")
    }

    func testDeriveTreatsEmptyValuesAsMissing() {
        let sessionId = HookSession.derive(
            environmentSessionId: "",
            stdinSessionId: "",
            appId: "MyApp")
        XCTAssertEqual(sessionId, "MyApp")
    }
}
