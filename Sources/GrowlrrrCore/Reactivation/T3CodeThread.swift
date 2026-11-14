import Foundation

/// A T3 Code thread, as located by the JSON `t3 thread show <id> --json`
/// prints.
///
/// That JSON carries the thread's hosted web link
/// (`https://app.t3.codes/threads/<environment>/<thread>`). The link is the
/// one place the CLI reports the environment id, which every way of opening
/// the thread needs alongside the thread id.
public struct T3CodeThread: Equatable {
    /// Allowed alphabet of an environment or thread id. The ids are embedded
    /// in a `sh -c` command, so anything outside it is rejected.
    private static let idCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

    private static let hostCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.")

    /// Scheme, host, and any explicit port of the hosted link, e.g.
    /// `https://app.t3.codes`.
    public let origin: String
    public let environmentId: String
    public let threadId: String

    public init?(threadShowOutput: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: threadShowOutput) as? [String: Any],
              let thread = json["thread"] as? [String: Any],
              let link = thread["link"] as? String,
              let components = URLComponents(string: link),
              let origin = Self.origin(of: components) else {
            return nil
        }

        let segments = components.path.split(separator: "/").map(String.init)
        guard segments.count == 3, segments[0] == "threads",
              Self.isPlainId(segments[1]), Self.isPlainId(segments[2]) else {
            return nil
        }

        self.origin = origin
        self.environmentId = segments[1]
        self.threadId = segments[2]
    }

    /// The shell command that opens the thread in the T3 Code desktop app.
    /// The desktop app answers the hosted link's path under its `t3code:`
    /// URL scheme, switching its window to the thread and bringing the
    /// window forward.
    public var desktopAppRevealCommand: String {
        "open 't3code://threads/\(environmentId)/\(threadId)'"
    }

    /// The shell command that opens the thread's hosted link in one Safari
    /// "Add to Dock" web app, named by the path of its app bundle. Several
    /// web apps can be made from the same site, so the link alone does not
    /// say which one to bring forward.
    public func webAppRevealCommand(appPath: String) -> String {
        let link = "\(origin)/threads/\(environmentId)/\(threadId)"
        return "open -a \(ReactivationContext.shellQuoted(appPath)) '\(link)'"
    }

    /// The origin a Safari "Add to Dock" web app was made from, read from
    /// the web manifest Safari stores in the app bundle's Info.plist. Nil
    /// for an app that is not a web app. A web app can show this thread
    /// when its origin equals the thread's `origin`.
    public static func webAppOrigin(infoPlist: Data) -> String? {
        guard let plist = try? PropertyListSerialization.propertyList(from: infoPlist, format: nil)
                as? [String: Any],
              let manifest = plist["Manifest"] as? [String: Any],
              let startURL = manifest["start_url"] as? String,
              let components = URLComponents(string: startURL) else {
            return nil
        }
        return origin(of: components)
    }

    private static func isPlainId(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy(idCharacters.contains)
    }

    private static func origin(of components: URLComponents) -> String? {
        guard let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = components.host?.lowercased(), !host.isEmpty,
              host.unicodeScalars.allSatisfy(hostCharacters.contains) else {
            return nil
        }
        guard let port = components.port else {
            return "\(scheme)://\(host)"
        }
        return "\(scheme)://\(host):\(port)"
    }
}
