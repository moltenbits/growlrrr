import Foundation

/// Busts the macOS caches that keep drawing an app bundle's previous icon.
///
/// Rewriting `Contents/Resources/AppIcon.icns` only touches a file nested
/// inside the bundle, so to macOS the bundle looks unchanged and every cache
/// layer keeps serving the old art. Getting the new icon on screen takes all
/// three steps, in order:
///
/// 1. Advance the bundle's own modification time (`touchBundle`) — the cache
///    key most layers consult.
/// 2. Delete iconservicesagent's persistent stores (`flushIconStores`) — the
///    agent outlives every daemon restart and its on-disk store outlives the
///    agent, so a warm store keeps answering with stale art no matter what the
///    mtime says. Observed directly: a store three days old survived an icon
///    change, an mtime bump, and both daemon restarts, and Notification Center
///    stayed stale until the store was deleted.
/// 3. Restart the notification daemons (`restartNotificationServices`) so they
///    re-request icons instead of drawing from process-local state.
public enum IconCache {
    /// Background services that hold their own copy of an app's notification icon.
    ///
    /// Deliberately excludes Dock and Finder: custom growlrrr bundles are
    /// `LSUIElement` agents that appear in neither, so restarting them would be
    /// user-visible churn for no benefit.
    public static let notificationServices = ["usernoted", "NotificationCenter"]

    /// Directory names iconservicesagent uses for its persistent icon stores.
    public static let iconStoreNames: Set<String> = [
        "com.apple.iconservicesagent",
        "com.apple.iconservices",
    ]

    /// Advance the bundle's modification time so macOS treats its cached icon as stale.
    ///
    /// Sets the date explicitly rather than shelling out to `touch`, which also
    /// avoids the filesystem-granularity race where two updates in the same
    /// second leave the mtime unchanged.
    public static func touchBundle(at bundlePath: URL) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: bundlePath.path
        )
    }

    /// Find iconservicesagent's persistent stores under `root`.
    ///
    /// Stores live in per-user cache directories shaped like
    /// `/var/folders/xx/yyyy/C/com.apple.iconservices*`. Only directories whose
    /// parent is `C` (DARWIN_USER_CACHE_DIR) qualify — the identically named
    /// `T/` siblings are the agent's live temp directories and must be left
    /// alone.
    public static func iconStorePaths(under root: URL, maxDepth: Int = 5) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }  // other users' dirs are unreadable; keep walking
        ) else {
            return []
        }

        var found: [URL] = []
        for case let url as URL in enumerator {
            if enumerator.level > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            guard iconStoreNames.contains(url.lastPathComponent),
                  url.deletingLastPathComponent().lastPathComponent == "C"
            else { continue }

            found.append(url)
            enumerator.skipDescendants()
        }
        return found.sorted { $0.path < $1.path }
    }

    /// Delete iconservicesagent's persistent stores so icons are re-read from
    /// their bundles. The system rebuilds the stores lazily on demand.
    ///
    /// Best-effort per store: one that cannot be removed just stays stale.
    /// Returns the stores actually removed.
    @discardableResult
    public static func flushIconStores(under root: URL = URL(fileURLWithPath: "/var/folders")) -> [URL] {
        var removed: [URL] = []
        for store in iconStorePaths(under: root) {
            do {
                try FileManager.default.removeItem(at: store)
                removed.append(store)
            } catch {
                continue
            }
        }
        return removed
    }

    /// Restart the notification daemons so they re-read app icons.
    ///
    /// Best-effort: these are launchd-managed and come back on their own, and a
    /// failure here leaves an icon stale rather than the app broken.
    public static func restartNotificationServices() {
        for service in notificationServices {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            process.arguments = [service]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }
}
