import ArgumentParser
import Foundation
import GrowlrrrCore

// MARK: - Hook Command Group

extension Growlrrr {
    struct Hook: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "hook",
            abstract: "Commands designed for use as tool hooks (e.g. Claude Code)",
            subcommands: [Notify.self, Dismiss.self]
        )
    }
}

// MARK: - Hook Notify

extension Growlrrr.Hook {
    struct Notify: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "notify",
            abstract: "Send a notification from JSON on stdin"
        )

        @Option(name: .shortAndLong, help: "Notification title (defaults to appId if set, otherwise 'Growlrrr')")
        var title: String?

        @Option(name: .long, help: "Sound to play (default, none, or sound name)")
        var sound: String?

        @Option(name: .customLong("appId"), help: "Use a custom app (create with 'grrr apps add')")
        var appId: String?

        @Flag(name: .long, inversion: .prefixedNo, help: "Reactivate the terminal window when notification is clicked")
        var reactivate: Bool = true

        @Flag(name: .long, help: "Replace any existing notification instead of stacking a new one")
        var replace: Bool = false

        func run() async throws {
            // Read JSON from stdin (blocks until EOF).
            // Supports two schemas:
            //   Stop event:         {"hook_event_name":"Stop", "last_assistant_message":"..."}
            //   Notification event: {"title":"...", "message":"..."}
            let stdinData = FileHandle.standardInput.readDataToEndOfFile()
            guard !stdinData.isEmpty else {
                fputs("Error: No input on stdin. Pipe JSON with title/message fields.\n", stderr)
                throw ExitCode(1)
            }

            let subtitle: String?
            let message: String
            do {
                guard let json = try JSONSerialization.jsonObject(with: stdinData) as? [String: Any] else {
                    fputs("Error: stdin must be a JSON object\n", stderr)
                    throw ExitCode(1)
                }

                let eventName = json["hook_event_name"] as? String

                if eventName == "Stop" {
                    // Stop event — Claude finished responding
                    subtitle = nil
                    message = "Claude is ready"
                } else {
                    // Notification event or generic JSON
                    subtitle = json["title"] as? String
                    message = (json["message"] as? String) ?? "Notification"
                }
            } catch let error as ExitCode {
                throw error
            } catch {
                fputs("Error: Invalid JSON on stdin: \(error.localizedDescription)\n", stderr)
                throw ExitCode(1)
            }

            // Resolve title: explicit --title wins, then appId, then "Growlrrr"
            let resolvedTitle = title ?? appId ?? "Growlrrr"

            // Derive session ID: env var > appId > "default".
            // Using appId ensures each custom app gets its own tracking file,
            // preventing cross-session dismiss conflicts between Claude Code instances.
            let sessionId = ProcessInfo.processInfo.environment["GROWLRRR_SESSION_ID"] ?? appId ?? "default"
            let identifier = replace ? "growlrrr-hook" : "growlrrr-hook-\(sessionId)"

            // Build reactivate script
            var executeCommand: String? = nil
            if reactivate {
                executeCommand = ReactivateScript.generate()
            }

            // Handle custom app
            if let appId = appId {
                guard CustomAppBundle.bundleExists(forAppName: appId) else {
                    fputs("Error: Custom app '\(appId)' not found\n", stderr)
                    throw ExitCode(1)
                }

                var args = ["send", "--title", resolvedTitle, "--identifier", identifier]
                if let subtitle = subtitle {
                    args += ["--subtitle", subtitle]
                }
                if let sound = sound {
                    args += ["--sound", sound]
                }
                if reactivate {
                    args += ["--reactivate"]
                }
                args += ["--appId", appId, message]

                do {
                    try CustomAppBundle.runNotification(
                        appName: appId,
                        iconPath: nil,
                        arguments: args
                    )
                } catch {
                    fputs("Error running from custom app: \(error.localizedDescription)\n", stderr)
                    throw ExitCode(1)
                }
                return
            }

            let config = NotificationConfig(
                message: message,
                title: resolvedTitle,
                subtitle: subtitle,
                sound: SoundOption.from(sound),
                imagePath: nil,
                open: nil,
                execute: executeCommand,
                identifier: identifier,
                threadId: nil,
                category: nil
            )

            let service = NotificationService()

            do {
                try await service.requestAuthorization()
            } catch GrowlrrrError.authorizationDenied {
                fputs("Error: Notification permission denied.\n", stderr)
                fputs("Run: growlrrr authorize --open-settings\n", stderr)
                throw ExitCode(1)
            }

            let notificationId = try await service.send(config)
            try await service.waitForDelivery(identifier: notificationId)

            // Clear any residual pending request and give the notification
            // system a RunLoop cycle to fully process the removal before the
            // process exits. Without this, app.terminate() can race ahead of
            // the removal and macOS will re-deliver the pending trigger.
            await service.clearPending(identifiers: [notificationId])
            await MainActor.run {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            }

        }
    }
}

// MARK: - Hook Dismiss

extension Growlrrr.Hook {
    struct Dismiss: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "dismiss",
            abstract: "Clear the notification for the current session"
        )

        @Option(name: .customLong("appId"), help: "Custom app to clear from")
        var appId: String?

        func run() async throws {
            let sessionId = ProcessInfo.processInfo.environment["GROWLRRR_SESSION_ID"] ?? appId ?? "default"

            // Derive the notification identifiers — clear both possible formats
            // in case --replace was used on the notify side
            let identifiers = [
                "growlrrr-hook-\(sessionId)",
                "growlrrr-hook",
            ]

            if let appId = appId {
                // Clear from custom app bundle
                let clearProcess = Process()
                clearProcess.executableURL = CustomAppBundle.executablePath(forAppName: appId)
                clearProcess.arguments = ["clear", "--delivered"] + identifiers
                clearProcess.standardOutput = FileHandle.nullDevice
                clearProcess.standardError = FileHandle.nullDevice
                try? clearProcess.run()
                clearProcess.waitUntilExit()
            } else {
                // Clear from main app
                let service = NotificationService()
                await service.clearDelivered(identifiers: identifiers)
                await MainActor.run {
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
                }
            }
        }
    }
}
