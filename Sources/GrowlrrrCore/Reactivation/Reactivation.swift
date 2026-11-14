import Foundation

/// Chooses the reactivation method for a notification and asks it what a
/// click should do.
public struct Reactivation {
    /// Names allowed for a terminal program activated by name; the name is
    /// embedded in a `sh -c` command.
    private static let programNameCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 ._-")

    private let methods: [ReactivationMethod]
    private let warn: (String) -> Void

    public init(
        methods: [ReactivationMethod] = ReactivationMethods.discover(),
        warn: @escaping (String) -> Void = { FileHandle.standardError.write(Data("\($0)\n".utf8)) }
    ) {
        self.methods = methods
        self.warn = warn
    }

    /// The shell command a click on the notification being sent should run,
    /// or nil when the click should do nothing.
    public func clickCommand(in context: ReactivationContext) -> String? {
        guard let method = method(for: context) else {
            return hostAppCommand(in: context)
        }
        return method.clickCommand(in: context)
    }

    /// Tells the method that would handle a click that a prompt was just
    /// submitted.
    public func promptSubmitted(in context: ReactivationContext) {
        method(for: context)?.promptSubmitted(in: context)
    }

    /// The applicable method in the innermost layer.
    private func method(for context: ReactivationContext) -> ReactivationMethod? {
        let applicable = methods.filter { $0.applies(in: context) }
        guard let innermostLayer = applicable.map({ type(of: $0).layer }).max() else {
            return nil
        }

        // Methods in one layer are meant to be mutually exclusive. If two
        // apply anyway there is no telling which is right, so pick the same
        // one every time and say so.
        let candidates = applicable
            .filter { type(of: $0).layer == innermostLayer }
            .sorted { name(of: $0) < name(of: $1) }
        if candidates.count > 1 {
            let names = candidates.map(name(of:)).joined(separator: ", ")
            warn("Warning: several reactivation methods apply (\(names)); using \(name(of: candidates[0]))")
        }
        return candidates[0]
    }

    /// What a click does when no method knows the host: bring forward the
    /// app that is running the process that sent the notification.
    private func hostAppCommand(in context: ReactivationContext) -> String? {
        if let hostApp = context.hostApp {
            return "open -a \(ReactivationContext.shellQuoted(hostApp.path))"
        }
        // A shell detached from its terminal has no app among its parents,
        // but still inherits the terminal's name.
        if let programName = context.environment["TERM_PROGRAM"], !programName.isEmpty,
           programName.unicodeScalars.allSatisfy(Self.programNameCharacters.contains) {
            return "osascript -e 'tell application \"\(programName)\" to activate'"
        }
        return nil
    }

    private func name(of method: ReactivationMethod) -> String {
        String(describing: type(of: method))
    }
}
