import Foundation

/// Somewhere a notification can be sent from that growlrrr knows something
/// about: a particular terminal, or a particular app that runs agents. An
/// adapter says how a click on the notification gets back to it.
///
/// To add an adapter, add a `final class` that conforms to this protocol
/// anywhere in GrowlrrrCore. Every conforming class is found at runtime (see
/// `ApplicationAdapters.discover`), which is why adapters are classes.
public protocol ApplicationAdapter: AnyObject {
    init()

    /// How deeply this adapter is nested. Only matters when several adapters
    /// apply to the same notification; the default, `.terminal`, is right
    /// for a terminal.
    static var layer: AdapterLayer { get }

    /// Whether the notification is being sent from this adapter.
    /// Keep it cheap: usually a look at one environment variable.
    func applies(in context: AdapterContext) -> Bool

    /// The shell command a click on the notification should run. Called
    /// while the notification is being sent, so anything about the current
    /// window that the click will need has to be captured now. Return nil
    /// to leave the click without an action.
    func clickCommand(in context: AdapterContext) -> String?

    /// Whether this adapter's hook belongs to a conversation that should
    /// notify. Adapters may also run internal jobs, such as title generation.
    func shouldNotify(in context: AdapterContext) -> Bool

    /// Called when a prompt is submitted from this adapter (`grrr hook
    /// dismiss`), for adapters that need to remember something from that
    /// moment — see `AdapterContext.frontmostApp` and `store(for:)`.
    func promptSubmitted(in context: AdapterContext)
}

extension ApplicationAdapter {
    public static var layer: AdapterLayer { .terminal }

    public func shouldNotify(in context: AdapterContext) -> Bool { true }

    public func promptSubmitted(in context: AdapterContext) {}
}

/// Adapters nest: a terminal can be running a program that runs agents in its
/// own windows, and everything inside inherits the terminal's environment
/// variables. When adapters for more than one layer apply, the innermost
/// layer is where the person was working, so it wins.
public enum AdapterLayer: Int, Comparable {
    /// A terminal emulator.
    case terminal
    /// An app that runs agents and has its own way of showing them, which
    /// may itself have been started from a terminal.
    case agentApp

    public static func < (lhs: AdapterLayer, rhs: AdapterLayer) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
