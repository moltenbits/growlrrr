import GrowlrrrCore
import XCTest

final class HookStdinPolicyTests: XCTestCase {
  func testMessageWithoutGateNeverReadsStdin() {
    // Regression: a held-open pipe must not block `--message` when no gate needs the bytes.
    XCTAssertFalse(HookStdinPolicy.shouldRead(hasMessage: true, hasGate: false, isTerminal: false))
    XCTAssertFalse(HookStdinPolicy.shouldRead(hasMessage: true, hasGate: false, isTerminal: true))
  }

  func testMessageWithGateReadsPipedStdinOnly() {
    XCTAssertTrue(HookStdinPolicy.shouldRead(hasMessage: true, hasGate: true, isTerminal: false))
    XCTAssertFalse(HookStdinPolicy.shouldRead(hasMessage: true, hasGate: true, isTerminal: true))
  }

  func testNoMessageAlwaysReadsStdin() {
    XCTAssertTrue(HookStdinPolicy.shouldRead(hasMessage: false, hasGate: false, isTerminal: false))
    XCTAssertTrue(HookStdinPolicy.shouldRead(hasMessage: false, hasGate: true, isTerminal: false))
    XCTAssertTrue(HookStdinPolicy.shouldRead(hasMessage: false, hasGate: false, isTerminal: true))
  }
}
