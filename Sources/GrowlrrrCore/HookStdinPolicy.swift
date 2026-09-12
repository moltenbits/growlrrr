/// Decides whether `grrr hook notify` consumes stdin.
///
/// Without `--message` the hook JSON on stdin is the only source of content,
/// so it is always read. With `--message` stdin is optional and is normally
/// ignored; it is consumed only when a `--gate` needs the bytes and something
/// is actually piped in. So a terminal, or a held-open pipe when no gate is
/// configured, never blocks. A gated pipe is read to EOF on purpose: the gate
/// must receive the exact bytes.
package enum HookStdinPolicy {
  package static func shouldRead(hasMessage: Bool, hasGate: Bool, isTerminal: Bool) -> Bool {
    if !hasMessage { return true }
    return hasGate && !isTerminal
  }
}
