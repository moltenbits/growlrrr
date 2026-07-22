import Foundation

/// Busts the macOS caches that keep drawing an app bundle's previous icon.
///
/// macOS keys its icon caches on the `.app` bundle's own modification time.
/// Rewriting `Contents/Resources/AppIcon.icns` only touches a nested file, so
/// the bundle still looks unchanged and Notification Center goes on drawing the
/// old art indefinitely — the new icon lands on disk but never on screen.
public enum IconCache {
    /// Background services that hold their own copy of an app's notification icon.
    ///
    /// Deliberately excludes Dock and Finder: custom growlrrr bundles are
    /// `LSUIElement` agents that appear in neither, so restarting them would be
    /// user-visible churn for no benefit.
    public static let notificationServices = ["usernoted", "NotificationCenter"]

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
