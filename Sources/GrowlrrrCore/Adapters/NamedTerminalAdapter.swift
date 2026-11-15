import Foundation

/// Terminals with no way to address a window or tab: the click brings the
/// app forward. Keyed on TERM_PROGRAM rather than the parent processes, so
/// it also works for a shell that has been detached from its terminal.
public final class NamedTerminalAdapter: ApplicationAdapter {
    /// TERM_PROGRAM values and the macOS app each belongs to.
    private static let appNames: [String: String] = [
        "WarpTerminal": "Warp",
        "Alacritty": "Alacritty",
        "kitty": "kitty",
    ]

    public init() {}

    public func applies(in context: AdapterContext) -> Bool {
        appName(in: context) != nil
    }

    public func clickCommand(in context: AdapterContext) -> String? {
        appName(in: context).map { "osascript -e 'tell application \"\($0)\" to activate'" }
    }

    private func appName(in context: AdapterContext) -> String? {
        context.environment["TERM_PROGRAM"].flatMap { Self.appNames[$0] }
    }
}
