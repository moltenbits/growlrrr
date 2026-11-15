import Foundation

/// One way of getting back to where a notification was sent from: a
/// particular terminal, or a particular app that runs agents.
///
/// To add a method, add a `final class` that conforms to this protocol
/// anywhere in GrowlrrrCore. Every conforming class is found at runtime (see
/// `ReactivationMethods.discover`), which is why methods are classes.
public protocol ReactivationMethod: AnyObject {
    init()

    /// How deeply the host this method knows about is nested. Only matters
    /// when several methods apply to the same notification; the default,
    /// `.terminal`, is right for a method that reactivates a terminal.
    static var layer: ReactivationLayer { get }

    /// Whether the notification is being sent from this method's host.
    /// Keep it cheap: usually a look at one environment variable.
    func applies(in context: ReactivationContext) -> Bool

    /// The shell command a click on the notification should run. Called
    /// while the notification is being sent, so anything about the current
    /// window that the click will need has to be captured now. Return nil
    /// to leave the click without an action.
    func clickCommand(in context: ReactivationContext) -> String?

    /// Whether this host's hook belongs to a conversation that should
    /// notify. Hosts may also run internal jobs, such as title generation.
    func shouldNotify(in context: ReactivationContext) -> Bool

    /// Called when a prompt is submitted from this method's host (`grrr hook
    /// dismiss`), for methods that need to remember something from that
    /// moment — see `ReactivationContext.frontmostApp` and `store(for:)`.
    func promptSubmitted(in context: ReactivationContext)
}

extension ReactivationMethod {
    public static var layer: ReactivationLayer { .terminal }

    public func shouldNotify(in context: ReactivationContext) -> Bool { true }

    public func promptSubmitted(in context: ReactivationContext) {}
}

/// Hosts nest: a terminal can be running a program that runs agents in its
/// own windows, and everything inside inherits the terminal's environment
/// variables. When methods for more than one layer apply, the innermost
/// layer is where the person was working, so it wins.
public enum ReactivationLayer: Int, Comparable {
    /// A terminal emulator.
    case terminal
    /// An app that runs agents and has its own way of showing them, which
    /// may itself have been started from a terminal.
    case agentHost

    public static func < (lhs: ReactivationLayer, rhs: ReactivationLayer) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum ReactivationMethods {
    /// One instance of every class in this binary that conforms to
    /// `ReactivationMethod`.
    ///
    /// Swift cannot list a protocol's conforming types, but every Swift
    /// class is registered with the Objective-C runtime, which can list the
    /// classes of one binary. Only growlrrr's own binary is searched.
    public static func discover() -> [ReactivationMethod] {
        var image = Dl_info()
        guard dladdr(#dsohandle, &image) != 0, let imagePath = image.dli_fname else {
            return []
        }
        var count: UInt32 = 0
        guard let classNames = objc_copyClassNamesForImage(imagePath, &count) else {
            return []
        }
        defer { free(classNames) }

        return (0..<Int(count)).compactMap { index in
            (objc_lookUpClass(classNames[index]) as? ReactivationMethod.Type)?.init()
        }
    }
}
