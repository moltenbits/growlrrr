/// Decides whether `grrr hook notify` consumes stdin.
///
/// Without `--message` the hook JSON on stdin is the only source of content,
/// so it is always read. With `--message` stdin is optional and is normally
/// ignored; it is consumed only when a `--gate` needs the bytes and something
/// is actually piped in, so a terminal or a held-open pipe never blocks.
public enum HookStdinPolicy {
  public static func shouldRead(hasMessage: Bool, hasGate: Bool, isTerminal: Bool) -> Bool {
    if !hasMessage { return true }
    return hasGate && !isTerminal
  }
}
