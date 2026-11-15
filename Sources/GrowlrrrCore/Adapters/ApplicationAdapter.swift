import Foundation

/// What growlrrr knows about one application that notifications are sent
/// from: a particular terminal, or a particular app that runs agents. An
/// adapter supplies the command a click runs to get back to the
/// application, and can supply what the conversation there is called.
///
/// To add an adapter, add a `final class` that conforms to this protocol
/// anywhere in GrowlrrrCore. Every conforming class is found at runtime (see
/// `ApplicationAdapters.discover`), which is why adapters are classes.
public protocol ApplicationAdapter: AnyObject {
    init()

    /// How deeply this adapter's application is nested. Only matters when
    /// several adapters apply to the same notification; the default,
    /// `.terminal`, is right for a terminal.
    static var layer: AdapterLayer { get }

    /// Whether the notification is being sent from this adapter's
    /// application.
    /// Keep it cheap: usually a look at one environment variable.
    func applies(in context: AdapterContext) -> Bool

    /// The shell command a click on the notification should run. Called
    /// while the notification is being sent, so anything about the current
    /// window that the click will need has to be captured now. Return nil
    /// to leave the click without an action.
    func clickCommand(in context: AdapterContext) -> String?

    /// What the application calls the conversation a hook notification is
    /// about, such as a thread's title. `grrr hook notify` shows it as the
    /// subtitle in place of the line that says the agent is waiting. Nil,
    /// the default, leaves the notification as it is.
    func conversationName(in context: AdapterContext) -> String?

    /// Whether the hook belongs to a conversation that should notify. An
    /// application may also run internal jobs, such as title generation,
    /// that run the same hooks.
    func shouldNotify(in context: AdapterContext) -> Bool

    /// Called when a prompt is submitted from this adapter's application
    /// (`grrr hook dismiss`), for adapters that need to remember something
    /// from that
    /// moment — see `AdapterContext.frontmostApp` and `store(for:)`.
    func promptSubmitted(in context: AdapterContext)
}

extension ApplicationAdapter {
    public static var layer: AdapterLayer { .terminal }

    public func conversationName(in context: AdapterContext) -> String? { nil }

    public func shouldNotify(in context: AdapterContext) -> Bool { true }

    public func promptSubmitted(in context: AdapterContext) {}
}

/// Applications nest: a terminal can be running a program that runs agents
/// in its own windows, and everything inside inherits the terminal's
/// environment variables. When adapters for more than one layer apply, the
/// innermost layer is where the person was working, so it wins.
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
