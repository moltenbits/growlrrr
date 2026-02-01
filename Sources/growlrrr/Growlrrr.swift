import ArgumentParser
import AppKit
import Foundation
import UserNotifications

// Entry point that handles both notification-triggered launches and CLI
@main
struct GrowlrrrMain {
    static func main() {
        // Set up the notification center delegate to handle notification clicks
        let launchHandler = NotificationLaunchHandler.shared
        UNUserNotificationCenter.current().delegate = launchHandler

        // If launched with no arguments, we might have been launched by clicking a notification
        if CommandLine.arguments.count == 1 {
            // Run NSApplication event loop to receive notification callback
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)

            // Use a timer to exit if no notification is received
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if !launchHandler.handled {
                    // No notification, show help
                    Task {
                        await Growlrrr.main(["--help"])
                        app.terminate(nil)
                    }
                }
            }

            app.run()
            return
        }

        // Normal CLI flow - use NSApplication to run the event loop
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        Task {
            await Growlrrr.main()
            app.terminate(nil)
        }

        app.run()
    }
}

// Singleton handler for notification responses at launch
final class NotificationLaunchHandler: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationLaunchHandler()
    var handled = false

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        handled = true
        let userInfo = response.notification.request.content.userInfo

        // Execute command if present
        if let command = userInfo["execute"] as? String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            try? process.run()
            process.waitUntilExit()
        }

        // Open URL if present
        if let urlString = userInfo["open"] as? String,
           let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }

        completionHandler()

        // Exit the app after handling
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

struct Growlrrr: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "growlrrr",
        abstract: "A modern CLI tool for macOS notifications",
        version: "0.1.0",
        subcommands: [Send.self, List.self, Clear.self, Authorize.self, Apps.self],
        defaultSubcommand: Send.self
    )
}

// MARK: - Apps Command

extension Growlrrr {
    struct Apps: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "apps",
            abstract: "Manage custom notification apps",
            subcommands: [AppsAdd.self, AppsList.self, AppsRemove.self, AppsUpdate.self]
        )
    }

    struct AppsAdd: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "add",
            abstract: "Add or update a custom notification app"
        )

        @Option(name: .customLong("appId"), help: "App identifier (e.g., 'MyCIBot')")
        var appId: String

        @Option(name: .customLong("appIcon"), help: "Path to the app icon image")
        var appIcon: String

        func run() throws {
            // Validate app ID
            let validNameRegex = try! NSRegularExpression(pattern: "^[a-zA-Z][a-zA-Z0-9_-]*$")
            let nameRange = NSRange(appId.startIndex..., in: appId)
            guard validNameRegex.firstMatch(in: appId, range: nameRange) != nil else {
                fputs("Error: --appId must start with a letter and contain only letters, numbers, hyphens, or underscores\n", stderr)
                throw ExitCode(1)
            }

            guard FileManager.default.fileExists(atPath: appIcon) else {
                fputs("Error: Icon file not found: \(appIcon)\n", stderr)
                throw ExitCode(1)
            }

            // Create or update the custom app bundle
            do {
                _ = try CustomAppBundle.ensureBundle(appName: appId, iconPath: appIcon)
                print("Created custom app '\(appId)'")
                print("Bundle: \(CustomAppBundle.bundlePath(forAppName: appId).path)")
                print("\nUse it with: growlrrr --appId \(appId) \"Your message\"")
            } catch {
                fputs("Error creating custom app: \(error.localizedDescription)\n", stderr)
                throw ExitCode(1)
            }
        }
    }

    struct AppsList: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List custom notification apps"
        )

        @Flag(name: .long, help: "Output as JSON")
        var json: Bool = false

        func run() throws {
            let appsDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".growlrrr")
                .appendingPathComponent("apps")

            guard FileManager.default.fileExists(atPath: appsDir.path) else {
                if json {
                    print("[]")
                } else {
                    print("No custom apps found")
                }
                return
            }

            let contents = try FileManager.default.contentsOfDirectory(
                at: appsDir,
                includingPropertiesForKeys: nil
            )

            let apps = contents
                .filter { $0.pathExtension == "app" }
                .map { $0.deletingPathExtension().lastPathComponent }
                .sorted()

            if apps.isEmpty {
                if json {
                    print("[]")
                } else {
                    print("No custom apps found")
                }
                return
            }

            if json {
                let appInfos = apps.map { name in
                    [
                        "name": name,
                        "bundleId": "com.moltenbits.growlrrr.\(name)",
                        "path": appsDir.appendingPathComponent("\(name).app").path
                    ]
                }
                let data = try JSONSerialization.data(withJSONObject: appInfos, options: [.prettyPrinted, .sortedKeys])
                print(String(data: data, encoding: .utf8) ?? "[]")
            } else {
                print("Custom notification apps (~/.growlrrr/apps/):\n")
                for name in apps {
                    let bundleId = "com.moltenbits.growlrrr.\(name)"
                    let path = appsDir.appendingPathComponent("\(name).app").path
                    print("  \(name)")
                    print("    Bundle ID: \(bundleId)")
                    print("    Path: \(path)\n")
                }
            }
        }
    }

    struct AppsRemove: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "remove",
            abstract: "Remove a custom notification app"
        )

        @Argument(help: "Name of the custom app to remove (e.g., 'RedAlert')")
        var name: String

        @Flag(name: .long, help: "Skip confirmation prompt")
        var force: Bool = false

        func run() throws {
            let appPath = CustomAppBundle.bundlePath(forAppName: name)

            guard FileManager.default.fileExists(atPath: appPath.path) else {
                fputs("Error: Custom app '\(name)' not found\n", stderr)
                fputs("Run 'growlrrr apps list' to see available apps\n", stderr)
                throw ExitCode(1)
            }

            if !force {
                print("This will remove the custom app '\(name)' and its notification settings.")
                print("Bundle: \(appPath.path)")
                print("\nTo remove it from System Settings > Notifications, you may need to:")
                print("  1. Log out and log back in, OR")
                print("  2. Run: killall NotificationCenter")
                print("\nProceed? [y/N] ", terminator: "")

                guard let response = readLine()?.lowercased(), response == "y" || response == "yes" else {
                    print("Cancelled")
                    return
                }
            }

            // Unregister from Launch Services
            let lsregister = Process()
            lsregister.executableURL = URL(fileURLWithPath: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")
            lsregister.arguments = ["-u", appPath.path]
            lsregister.standardOutput = FileHandle.nullDevice
            lsregister.standardError = FileHandle.nullDevice
            try? lsregister.run()
            lsregister.waitUntilExit()

            // Remove the app bundle
            try FileManager.default.removeItem(at: appPath)

            print("Removed '\(name)'")
            print("\nTo clear from System Settings > Notifications, run:")
            print("  killall NotificationCenter")
        }
    }

    struct AppsUpdate: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "update",
            abstract: "Update all custom apps to use the latest growlrrr executable"
        )

        func run() throws {
            let customApps = CustomAppBundle.listCustomApps()

            if customApps.isEmpty {
                print("No custom apps to update")
                return
            }

            print("Updating \(customApps.count) custom app(s)...")

            do {
                let updated = try CustomAppBundle.updateAllBundles()
                if updated.isEmpty {
                    print("No apps needed updating")
                } else {
                    for name in updated {
                        print("  Updated: \(name)")
                    }
                    print("\nSuccessfully updated \(updated.count) app(s)")
                }
            } catch {
                fputs("Error updating apps: \(error.localizedDescription)\n", stderr)
                throw ExitCode(1)
            }
        }
    }
}

// MARK: - Authorize Command

extension Growlrrr {
    struct Authorize: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "authorize",
            abstract: "Request notification permissions or open System Settings"
        )

        @Flag(name: .long, help: "Open System Settings to notification preferences")
        var openSettings: Bool = false

        @Flag(name: .long, help: "Check current authorization status")
        var status: Bool = false

        func run() async throws {
            let service = NotificationService()

            if status {
                let authStatus = await service.checkAuthorizationStatus()
                switch authStatus {
                case .authorized:
                    print("Status: authorized")
                case .denied:
                    print("Status: denied")
                    print("Run 'growlrrr authorize --open-settings' to enable notifications")
                case .notDetermined:
                    print("Status: not determined")
                    print("Run 'growlrrr authorize' to request permission")
                case .provisional:
                    print("Status: provisional")
                case .ephemeral:
                    print("Status: ephemeral")
                @unknown default:
                    print("Status: unknown")
                }
                return
            }

            if openSettings {
                print("Opening System Settings...")
                await service.openNotificationSettings()
                return
            }

            // Request authorization
            do {
                try await service.requestAuthorization()
                print("Notifications authorized!")
            } catch GrowlrrrError.authorizationDenied {
                fputs("Notification permission denied.\n", stderr)
                fputs("To enable notifications, run:\n", stderr)
                fputs("  growlrrr authorize --open-settings\n", stderr)
                throw ExitCode(1)
            }
        }
    }
}

// MARK: - Send Command

extension Growlrrr {
    struct Send: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "send",
            abstract: "Send a notification"
        )

        @Argument(help: "The notification message body")
        var message: String

        @Option(name: .shortAndLong, help: "Notification title")
        var title: String?

        @Option(name: .shortAndLong, help: "Notification subtitle")
        var subtitle: String?

        @Option(name: .long, help: "Sound to play (default, none, or sound name)")
        var sound: String?

        @Option(name: .long, help: "Path to image attachment (appears on right side of notification)")
        var image: String?

        @Option(name: .customLong("appId"), help: "Use a custom app (create with 'growlrrr apps add')")
        var appId: String?

        @Option(name: .long, help: "URL to open when notification is clicked")
        var open: String?

        @Option(name: .long, help: "Shell command to execute when notification is clicked")
        var execute: String?

        @Option(name: .long, help: "Identifier for the notification (for updates/removal)")
        var identifier: String?

        @Option(name: .customLong("threadId"), help: "Thread identifier for grouping notifications")
        var threadId: String?

        @Option(name: .long, help: "Category identifier for actionable notifications")
        var category: String?

        @Flag(name: .long, help: "Wait for user interaction before exiting")
        var wait: Bool = false

        @Flag(name: .customLong("printId"), help: "Output notification identifier to stdout")
        var printId: Bool = false

        @Flag(name: .long, help: "Reactivate the terminal window when notification is clicked")
        var reactivate: Bool = false

        func run() async throws {
            // Handle custom app
            if let appId = appId {
                guard CustomAppBundle.bundleExists(forAppName: appId) else {
                    fputs("Error: Custom app '\(appId)' not found\n", stderr)
                    fputs("Create it first with: growlrrr apps add --appId \(appId) --appIcon <path>\n", stderr)
                    throw ExitCode(1)
                }

                // Run notification from custom app bundle
                do {
                    try CustomAppBundle.runNotification(
                        appName: appId,
                        iconPath: nil,
                        arguments: Array(CommandLine.arguments.dropFirst())
                    )
                    // runNotification calls exit(), so we shouldn't reach here
                } catch {
                    fputs("Error running from custom app: \(error.localizedDescription)\n", stderr)
                    throw ExitCode(1)
                }
            } else {
                try await sendNotification()
            }
        }

        private func sendNotification() async throws {
            // Determine execute command (may be overridden by --reactivate)
            var executeCommand = execute

            if reactivate {
                if let reactivateScript = generateReactivateScript() {
                    // Combine with existing execute if present
                    if let existing = executeCommand {
                        executeCommand = "\(reactivateScript) ; \(existing)"
                    } else {
                        executeCommand = reactivateScript
                    }
                }
            }

            let config = NotificationConfig(
                message: message,
                title: title,
                subtitle: subtitle,
                sound: SoundOption.from(sound),
                imagePath: image,
                open: open.flatMap { URL(string: $0) },
                execute: executeCommand,
                identifier: identifier ?? UUID().uuidString,
                threadId: threadId,
                category: category
            )

            let service = NotificationService()

            // Request authorization first
            do {
                try await service.requestAuthorization()
            } catch GrowlrrrError.authorizationDenied {
                fputs("Error: Notification permission denied.\n", stderr)
                fputs("To enable notifications, run:\n", stderr)
                fputs("  growlrrr authorize --open-settings\n", stderr)
                throw ExitCode(1)
            }

            // Send the notification
            let notificationId = try await service.send(config)

            if printId {
                print(notificationId)
            }

            if wait {
                // Wait for user interaction
                try await service.waitForInteraction(identifier: notificationId)
            } else {
                // Wait for notification to be delivered
                // The trigger has 0.1s delay, we need to let the run loop process it
                try await service.waitForDelivery(identifier: notificationId)
            }
        }

        private func generateReactivateScript() -> String? {
            let termProgram = ProcessInfo.processInfo.environment["TERM_PROGRAM"]

            switch termProgram {
            case "iTerm.app":
                return generateITermReactivateScript()
            case "Apple_Terminal":
                return generateTerminalReactivateScript()
            case "WarpTerminal":
                return "osascript -e 'tell application \"Warp\" to activate'"
            case "Alacritty":
                return "osascript -e 'tell application \"Alacritty\" to activate'"
            case "kitty":
                return "osascript -e 'tell application \"kitty\" to activate'"
            default:
                // Try to detect from parent process or fall back to generic activation
                if let bundleId = detectTerminalBundleId() {
                    return "osascript -e 'tell application id \"\(bundleId)\" to activate'"
                }
                return nil
            }
        }

        private func generateITermReactivateScript() -> String? {
            // Capture the current iTerm2 session ID
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", "tell application \"iTerm2\" to id of current session of current window"]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice

            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let sessionId = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !sessionId.isEmpty else {
                    // Fallback to just activating iTerm2
                    return "osascript -e 'tell application \"iTerm2\" to activate'"
                }

                // Generate AppleScript that finds and focuses this specific session
                // Use heredoc to preserve newlines which AppleScript requires
                return """
                    osascript <<'APPLESCRIPT'
                    tell application "iTerm2"
                        repeat with w in windows
                            repeat with t in tabs of w
                                repeat with s in sessions of t
                                    if id of s is "\(sessionId)" then
                                        select t
                                        select w
                                        activate
                                        return
                                    end if
                                end repeat
                            end repeat
                        end repeat
                    end tell
                    APPLESCRIPT
                    """
            } catch {
                return "osascript -e 'tell application \"iTerm2\" to activate'"
            }
        }

        private func generateTerminalReactivateScript() -> String? {
            // Capture the current Terminal.app window and tab
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", """
                tell application "Terminal"
                    set windowId to id of front window
                    set tabIndex to index of selected tab of front window
                    return (windowId as text) & "," & (tabIndex as text)
                end tell
                """]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice

            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !output.isEmpty else {
                    return "osascript -e 'tell application \"Terminal\" to activate'"
                }

                let parts = output.split(separator: ",")
                guard parts.count == 2,
                      let windowId = Int(parts[0]),
                      let tabIndex = Int(parts[1]) else {
                    return "osascript -e 'tell application \"Terminal\" to activate'"
                }

                // Generate AppleScript that finds and focuses this specific window/tab
                // Use heredoc to preserve newlines which AppleScript requires
                return """
                    osascript <<'APPLESCRIPT'
                    tell application "Terminal"
                        repeat with w in windows
                            if id of w is \(windowId) then
                                set selected tab of w to tab \(tabIndex) of w
                                set frontmost of w to true
                                activate
                                return
                            end if
                        end repeat
                    end tell
                    APPLESCRIPT
                    """
            } catch {
                return "osascript -e 'tell application \"Terminal\" to activate'"
            }
        }

        private func detectTerminalBundleId() -> String? {
            // Try to find the terminal by walking up the process tree
            var pid = getppid()
            while pid > 1 {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/bin/ps")
                task.arguments = ["-p", String(pid), "-o", "comm="]

                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = FileHandle.nullDevice

                do {
                    try task.run()
                    task.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let comm = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                        // Map common terminal process names to bundle IDs
                        switch comm {
                        case "iTerm2", "iTerm":
                            return "com.googlecode.iterm2"
                        case "Terminal":
                            return "com.apple.Terminal"
                        case "Warp":
                            return "dev.warp.Warp-Stable"
                        case "Alacritty":
                            return "org.alacritty"
                        case "kitty":
                            return "net.kovidgoyal.kitty"
                        default:
                            break
                        }
                    }
                } catch {
                    break
                }

                // Get parent PID
                let ppidTask = Process()
                ppidTask.executableURL = URL(fileURLWithPath: "/bin/ps")
                ppidTask.arguments = ["-p", String(pid), "-o", "ppid="]

                let ppidPipe = Pipe()
                ppidTask.standardOutput = ppidPipe
                ppidTask.standardError = FileHandle.nullDevice

                do {
                    try ppidTask.run()
                    ppidTask.waitUntilExit()

                    let data = ppidPipe.fileHandleForReading.readDataToEndOfFile()
                    if let ppidStr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       let newPid = Int32(ppidStr) {
                        pid = newPid
                    } else {
                        break
                    }
                } catch {
                    break
                }
            }
            return nil
        }
    }
}

// MARK: - List Command

extension Growlrrr {
    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List delivered notifications"
        )

        @Flag(name: .long, help: "List pending (scheduled) notifications instead of delivered")
        var pending: Bool = false

        @Flag(name: .long, help: "Output as JSON")
        var json: Bool = false

        func run() async throws {
            var allNotifications: [NotificationInfo] = []

            // Get notifications from current app
            let service = NotificationService()
            var currentNotifications = pending
                ? await service.listPending()
                : await service.listDelivered()

            // Determine current app name
            let currentAppName = CustomAppBundle.currentCustomAppName() ?? "growlrrr"

            // Tag with app name
            for i in currentNotifications.indices {
                currentNotifications[i].app = currentAppName
            }
            allNotifications.append(contentsOf: currentNotifications)

            // Only query other apps if running from main app (prevent recursion)
            if !CustomAppBundle.isRunningFromCustomApp() {
                let customApps = CustomAppBundle.listCustomApps()
                for appName in customApps {
                    do {
                        let args = pending ? ["list", "--pending", "--json"] : ["list", "--json"]
                        let output = try CustomAppBundle.runAndCapture(appName: appName, arguments: args)
                        if let data = output.data(using: .utf8),
                           var appNotifications = try? JSONDecoder().decode([NotificationInfo].self, from: data) {
                            // Tag with app name
                            for i in appNotifications.indices {
                                appNotifications[i].app = appName
                            }
                            allNotifications.append(contentsOf: appNotifications)
                        }
                    } catch {
                        // Skip apps that fail to respond
                    }
                }
            }

            let emptyMessage = pending ? "No pending notifications" : "No delivered notifications"

            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(allNotifications)
                print(String(data: data, encoding: .utf8) ?? "[]")
            } else {
                if allNotifications.isEmpty {
                    print(emptyMessage)
                } else {
                    for notification in allNotifications {
                        let appLabel = notification.app.map { "[\($0)] " } ?? ""
                        print("\(appLabel)\(notification.identifier): \(notification.title ?? "(no title)") - \(notification.body)")
                    }
                }
            }
        }
    }
}

// MARK: - Clear Command

extension Growlrrr {
    struct Clear: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "clear",
            abstract: "Clear notifications"
        )

        @Argument(help: "Notification identifier(s) to clear. If omitted, clears all.")
        var identifiers: [String] = []

        @Flag(name: .long, help: "Clear only pending (scheduled) notifications")
        var pending: Bool = false

        @Flag(name: .long, help: "Clear only delivered notifications")
        var delivered: Bool = false

        func run() async throws {
            let service = NotificationService()

            // Clear from current app
            if identifiers.isEmpty {
                // No identifiers specified - clear all of the specified type(s)
                if pending && !delivered {
                    await service.clearAllPending()
                } else if delivered && !pending {
                    await service.clearAllDelivered()
                } else {
                    // Default: clear all (both pending and delivered)
                    await service.clearAll()
                }
            } else {
                // Clear specific identifiers
                if pending && !delivered {
                    await service.clearPending(identifiers: identifiers)
                } else if delivered && !pending {
                    await service.clearDelivered(identifiers: identifiers)
                } else {
                    // Default: clear from both
                    await service.clearPending(identifiers: identifiers)
                    await service.clearDelivered(identifiers: identifiers)
                }
            }

            // Also clear from all custom apps if running from main app (prevent recursion)
            if !CustomAppBundle.isRunningFromCustomApp() {
                let customApps = CustomAppBundle.listCustomApps()
                for appName in customApps {
                    var args = ["clear"]
                    args.append(contentsOf: identifiers)
                    if pending && !delivered {
                        args.append("--pending")
                    } else if delivered && !pending {
                        args.append("--delivered")
                    }
                    _ = try? CustomAppBundle.runAndCapture(appName: appName, arguments: args)
                }
            }

            // Print summary
            if identifiers.isEmpty {
                if pending && !delivered {
                    print("Cleared all pending notifications")
                } else if delivered && !pending {
                    print("Cleared all delivered notifications")
                } else {
                    print("Cleared all notifications")
                }
            } else {
                print("Cleared \(identifiers.count) notification(s)")
            }
        }
    }
}
