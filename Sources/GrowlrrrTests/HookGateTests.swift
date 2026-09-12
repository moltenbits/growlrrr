import Foundation
import GrowlrrrCore
import XCTest

final class HookGateTests: XCTestCase {
  func testExitZeroProceeds() {
    XCTAssertEqual(HookGate.evaluate(command: "exit 0", input: Data()), .proceed)
  }

  func testExitOneSkips() {
    XCTAssertEqual(HookGate.evaluate(command: "exit 1", input: Data()), .skip)
  }

  func testOtherExitCodeProceedsWithWarning() {
    guard
      case .proceedWithWarning(let warning) = HookGate.evaluate(command: "exit 3", input: Data())
    else {
      return XCTFail("expected proceedWithWarning")
    }
    XCTAssertTrue(warning.contains("3"), "warning should name the exit code: \(warning)")
    XCTAssertTrue(warning.contains("exit 3"), "warning should name the gate command: \(warning)")
  }

  func testNonexistentCommandProceedsWithWarning() {
    let decision = HookGate.evaluate(command: "/nonexistent/growlrrr-gate-binary", input: Data())
    guard case .proceedWithWarning = decision else {
      return XCTFail("expected proceedWithWarning, got \(decision)")
    }
  }

  func testStdinBytesReachGateUnchanged() throws {
    let input = Data("{\"hook_event_name\":\"Stop\",\"bytes\":\"\u{00e9}\\n\"}\n".utf8)
    let capture = temporaryFile()
    let decision = HookGate.evaluate(command: "cat > '\(capture.path)'", input: input)
    XCTAssertEqual(decision, .proceed)
    XCTAssertEqual(try Data(contentsOf: capture), input)
  }

  func testGateStdoutDoesNotReachParentStdout() throws {
    let stdoutCapture = temporaryFile()
    let stderrCapture = temporaryFile()
    let decision = try withRedirectedStandardStreams(stdout: stdoutCapture, stderr: stderrCapture) {
      HookGate.evaluate(command: "echo to-stdout; echo to-stderr >&2", input: Data())
    }
    XCTAssertEqual(decision, .proceed)
    XCTAssertEqual(try String(contentsOf: stdoutCapture), "")
    let stderrText = try String(contentsOf: stderrCapture)
    XCTAssertTrue(
      stderrText.contains("to-stdout"), "gate stdout should be diverted to stderr: \(stderrText)")
    XCTAssertTrue(
      stderrText.contains("to-stderr"), "gate stderr should stay on stderr: \(stderrText)")
  }

  func testLargeStdoutBeforeReadingLargeStdinDoesNotDeadlock() throws {
    let megabyte = 1 << 20
    let input = Data(repeating: UInt8(ascii: "x"), count: megabyte)
    let stdoutCapture = temporaryFile()
    let stderrCapture = temporaryFile()
    // Write 1 MiB to stdout before touching stdin, then consume stdin and count it.
    let command =
      "head -c \(megabyte) /dev/zero; n=$(wc -c | tr -d ' '); [ \"$n\" -eq \(megabyte) ]"
    let decision = try withRedirectedStandardStreams(stdout: stdoutCapture, stderr: stderrCapture) {
      HookGate.evaluate(command: command, input: input)
    }
    XCTAssertEqual(decision, .proceed)
    XCTAssertEqual(try Data(contentsOf: stdoutCapture).count, 0)
  }

  func testGateThatNeverReadsLargeStdinStillCompletes() {
    let input = Data(repeating: UInt8(ascii: "x"), count: 1 << 20)
    XCTAssertEqual(HookGate.evaluate(command: "exit 1", input: input), .skip)
  }

  func testEvaluationLeavesSigpipeDispositionUnchanged() {
    var before = sigaction()
    sigaction(SIGPIPE, nil, &before)

    // A gate that exits without reading a large stdin makes our write hit EPIPE.
    XCTAssertEqual(
      HookGate.evaluate(command: "exit 1", input: Data(repeating: 0x78, count: 1 << 20)), .skip)

    var after = sigaction()
    sigaction(SIGPIPE, nil, &after)
    XCTAssertEqual(
      unsafeBitCast(before.__sigaction_u, to: Int.self),
      unsafeBitCast(after.__sigaction_u, to: Int.self),
      "evaluate must not change the process-wide SIGPIPE handler")
  }

  func testWarningStaysOnOneLineForMultilineCommand() {
    guard
      case .proceedWithWarning(let warning) = HookGate.evaluate(
        command: "true\nexit 3", input: Data())
    else {
      return XCTFail("expected proceedWithWarning")
    }
    XCTAssertFalse(warning.contains("\n"), warning)
    XCTAssertTrue(warning.contains("exited 3"), warning)
  }

  // MARK: - Helpers

  private func temporaryFile() -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("growlrrr-gate-\(UUID().uuidString)")
    FileManager.default.createFile(atPath: url.path, contents: nil)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }

  /// Runs `body` with the process's fd 1 and fd 2 pointed at the given files,
  /// restoring the originals afterwards.
  private func withRedirectedStandardStreams<T>(stdout: URL, stderr: URL, _ body: () -> T) throws
    -> T
  {
    fflush(Darwin.stdout)
    fflush(Darwin.stderr)
    let savedOut = dup(STDOUT_FILENO)
    let savedErr = dup(STDERR_FILENO)
    let outFD = open(stdout.path, O_WRONLY | O_TRUNC)
    let errFD = open(stderr.path, O_WRONLY | O_TRUNC)
    XCTAssertGreaterThanOrEqual(outFD, 0)
    XCTAssertGreaterThanOrEqual(errFD, 0)
    dup2(outFD, STDOUT_FILENO)
    dup2(errFD, STDERR_FILENO)
    defer {
      fflush(Darwin.stdout)
      fflush(Darwin.stderr)
      dup2(savedOut, STDOUT_FILENO)
      dup2(savedErr, STDERR_FILENO)
      close(savedOut)
      close(savedErr)
      close(outFD)
      close(errFD)
    }
    return body()
  }
}
