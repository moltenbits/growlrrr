import Foundation

/// What a hook command should do after consulting its `--gate` command.
public enum HookGateDecision: Equatable {
  /// The gate exited 0 (or there was no gate): do the work.
  case proceed
  /// The gate exited 1: skip the work and exit 0 quietly.
  case skip
  /// The gate could not be started or exited with a code other than 0 or 1.
  /// Do the work anyway, and print the warning to stderr; a broken gate must
  /// never silence the user.
  case proceedWithWarning(String)
}

/// Runs a user-supplied gate command and turns its exit status into a decision.
///
/// The gate runs through `/bin/sh -c` with the given bytes on its stdin. Its
/// stdout is diverted to this process's stderr so it can never leak into a
/// hook's stdout, which hosts such as Claude Code parse for decisions.
public enum HookGate {
  public static func evaluate(command: String, input: Data) -> HookGateDecision {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]

    let stdinPipe = Pipe()
    process.standardInput = stdinPipe
    // Redirect straight to descriptors: nothing to drain, so nothing to deadlock on.
    process.standardOutput = FileHandle.standardError
    process.standardError = FileHandle.standardError

    do {
      try process.run()
    } catch {
      return .proceedWithWarning(
        "Warning: could not start gate '\(command)': \(error.localizedDescription); proceeding")
    }

    // Feed stdin off the main thread so a gate that exits without reading a
    // large input cannot block us, and so waiting for exit never waits on the
    // write. A gate that exits early closes the read end; the write then
    // fails with EPIPE instead of killing us, since SIGPIPE is ignored.
    signal(SIGPIPE, SIG_IGN)
    let writer = stdinPipe.fileHandleForWriting
    let feeder = Thread {
      if !input.isEmpty {
        try? writer.write(contentsOf: input)
      }
      try? writer.close()
    }
    feeder.start()

    process.waitUntilExit()

    switch process.terminationStatus {
    case 0:
      return .proceed
    case 1:
      return .skip
    case let status:
      return .proceedWithWarning(
        "Warning: gate '\(command)' exited \(status); proceeding")
    }
  }
}
