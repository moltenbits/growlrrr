import Foundation

public enum AppVersion {
    /// Reported when no app bundle is present (bare `swift build` executable).
    public static let fallback = "0.0.0-dev"

    /// The version of the app bundle containing this executable, as stamped
    /// into CFBundleShortVersionString by scripts/bundle.sh. Source builds
    /// without a bundle report the fallback.
    public static func current() -> String {
        // Resolves when launched from inside the .app bundle.
        if let version = resolve(infoDictionary: Bundle.main.infoDictionary) {
            return version
        }
        // Through a CLI symlink, resolve the executable path and walk up
        // to the enclosing .app bundle.
        if let bundlePath = CustomAppBundle.findSourceBundle(),
           let bundle = Bundle(path: bundlePath),
           let version = resolve(infoDictionary: bundle.infoDictionary) {
            return version
        }
        return fallback
    }

    public static func resolve(infoDictionary: [String: Any]?) -> String? {
        infoDictionary?["CFBundleShortVersionString"] as? String
    }
}
