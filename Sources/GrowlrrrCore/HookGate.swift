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
        "Warning: could not start gate '\(displayable(command))': \(error.localizedDescription); proceeding"
      )
    }

    // Feed stdin off the main thread so a gate that exits without reading a
    // large input cannot block us, and so waiting for exit never waits on the
    // write. A gate that exits early closes the read end; F_SETNOSIGPIPE makes
    // the write fail with EPIPE on this descriptor alone instead of raising
    // SIGPIPE, so the process-wide signal disposition is left untouched.
    let writer = stdinPipe.fileHandleForWriting
    _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
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
        "Warning: gate '\(displayable(command))' exited \(status); proceeding")
    }
  }

  /// The command as it can appear inside a one-line warning: control
  /// characters are shown as escapes so a multiline gate cannot wrap the line.
  private static func displayable(_ command: String) -> String {
    var out = ""
    for scalar in command.unicodeScalars {
      switch scalar {
      case "\n": out += "\\n"
      case "\r": out += "\\r"
      case "\t": out += "\\t"
      case _ where scalar.value < 0x20 || scalar.value == 0x7F:
        out += String(format: "\\u%04X", scalar.value)
      default: out.unicodeScalars.append(scalar)
      }
    }
    return out
  }
}
