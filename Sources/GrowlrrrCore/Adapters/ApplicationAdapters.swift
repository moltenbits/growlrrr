import Foundation

/// The adapters growlrrr has. Works out which one knows the application a
/// notification is being sent from and puts questions about the
/// notification to it.
public struct ApplicationAdapters {
    /// Names allowed for a terminal program activated by name; the name is
    /// embedded in a `sh -c` command.
    private static let programNameCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 ._-")

    private let adapters: [ApplicationAdapter]
    private let warn: (String) -> Void

    public init(
        adapters: [ApplicationAdapter] = ApplicationAdapters.discover(),
        warn: @escaping (String) -> Void = { FileHandle.standardError.write(Data("\($0)\n".utf8)) }
    ) {
        self.adapters = adapters
        self.warn = warn
    }

    /// The shell command a click on the notification being sent should run,
    /// or nil when the click should do nothing.
    public func clickCommand(in context: AdapterContext) -> String? {
        guard let adapter = adapter(for: context) else {
            return parentAppCommand(in: context)
        }
        return adapter.clickCommand(in: context)
    }

    /// What the application the notification is being sent from calls the
    /// conversation, or nil when it has no name for it.
    public func conversationName(in context: AdapterContext) -> String? {
        adapter(for: context)?.conversationName(in: context)
    }

    /// An application's internal jobs may run the same hooks as user
    /// conversations.
    /// Only the innermost adapter knows whether such a hook should notify.
    public func shouldNotify(in context: AdapterContext) -> Bool {
        adapter(for: context)?.shouldNotify(in: context) ?? true
    }

    /// Tells the adapter that would handle a click that a prompt was just
    /// submitted.
    public func promptSubmitted(in context: AdapterContext) {
        adapter(for: context)?.promptSubmitted(in: context)
    }

    /// The applicable adapter in the innermost layer.
    private func adapter(for context: AdapterContext) -> ApplicationAdapter? {
        let applicable = adapters.filter { $0.applies(in: context) }
        guard let innermostLayer = applicable.map({ type(of: $0).layer }).max() else {
            return nil
        }

        // Adapters in one layer are meant to be mutually exclusive. If two
        // apply anyway there is no telling which is right, so pick the same
        // one every time and say so.
        let candidates = applicable
            .filter { type(of: $0).layer == innermostLayer }
            .sorted { name(of: $0) < name(of: $1) }
        if candidates.count > 1 {
            let names = candidates.map(name(of:)).joined(separator: ", ")
            warn("Warning: several adapters apply (\(names)); using \(name(of: candidates[0]))")
        }
        return candidates[0]
    }

    /// What a click does when no adapter applies: bring forward the
    /// app that is running the process that sent the notification.
    private func parentAppCommand(in context: AdapterContext) -> String? {
        if let parentApp = context.parentApp {
            return "open -a \(AdapterContext.shellQuoted(parentApp.path))"
        }
        // A shell detached from its terminal has no app among its parents,
        // but still inherits the terminal's name.
        if let programName = context.environment["TERM_PROGRAM"], !programName.isEmpty,
           programName.unicodeScalars.allSatisfy(Self.programNameCharacters.contains) {
            return "osascript -e 'tell application \"\(programName)\" to activate'"
        }
        return nil
    }

    private func name(of adapter: ApplicationAdapter) -> String {
        String(describing: type(of: adapter))
    }

    /// One instance of every class in this binary that conforms to
    /// `ApplicationAdapter`.
    ///
    /// Swift cannot list a protocol's conforming types, but every Swift
    /// class is registered with the Objective-C runtime, which can list the
    /// classes of one binary. Only growlrrr's own binary is searched.
    public static func discover() -> [ApplicationAdapter] {
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
            (objc_lookUpClass(classNames[index]) as? ApplicationAdapter.Type)?.init()
        }
    }
}
