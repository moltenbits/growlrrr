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

        /// Consults a `--gate` command. Returns false when the gate says to
        /// skip; a broken gate warns on stderr and lets the work proceed.
        static func passesGate(_ command: String, input: Data) -> Bool {
            switch HookGate.evaluate(command: command, input: input) {
            case .proceed:
                return true
            case .skip:
                return false
            case .proceedWithWarning(let warning):
                fputs("\(warning)\n", stderr)
                return true
            }
        }
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

        @Option(name: .shortAndLong, help: "Notification message. When set, stdin JSON is optional.")
        var message: String?

        @Option(name: .long, help: "Sound to play (default, none, or sound name)")
        var sound: String?

        @Option(name: .customLong("appId"), help: "Use a custom app (create with 'grrr apps add')")
        var appId: String?

        @Flag(name: .long, inversion: .prefixedNo, help: "Reactivate the terminal window when notification is clicked")
        var reactivate: Bool = true

        @Flag(name: .long, help: "Replace any existing notification instead of stacking a new one")
        var replace: Bool = false

        @Flag(name: .long, help: "Parse stdin as Codex hook JSON")
        var codex: Bool = false

        @Option(
            name: .long,
            help: ArgumentHelp(
                "Command to consult before sending; exit 0 sends, 1 skips quietly, anything else sends with a warning",
                discussion: "Runs through /bin/sh -c with this command's stdin piped to it. Its stdout is diverted to stderr."))
        var gate: String?

        func run() async throws {
            // Read stdin up front so the gate sees the same bytes we do.
            // See HookStdinPolicy for when --message lets us skip it.
            let stdinData: Data
            if HookStdinPolicy.shouldRead(
                hasMessage: message != nil, hasGate: gate != nil, isTerminal: isatty(STDIN_FILENO) != 0)
            {
                stdinData = FileHandle.standardInput.readDataToEndOfFile()
            } else {
                stdinData = Data()
            }

            // The gate runs once, here, before any --appId re-execution; the
            // inner invocation is a plain `send` and never sees --gate.
            if let gate, !Growlrrr.Hook.passesGate(gate, input: stdinData) {
                return
            }

            let subtitle: String?
            let resolvedMessage: String
            let stdinSessionId: String?
            if let message {
                subtitle = nil
                resolvedMessage = message
                stdinSessionId = nil
            } else {
                // Supports two schemas:
                //   Stop event:         {"hook_event_name":"Stop", "last_assistant_message":"..."}
                //   Notification event: {"title":"...", "message":"..."}
                guard !stdinData.isEmpty else {
                    fputs("Error: No input on stdin. Pipe JSON with title/message fields.\n", stderr)
                    throw ExitCode(1)
                }

                do {
                    guard let json = try JSONSerialization.jsonObject(with: stdinData) as? [String: Any] else {
                        fputs("Error: stdin must be a JSON object\n", stderr)
                        throw ExitCode(1)
                    }

                    let content = codex
                        ? HookNotificationContentResolver.codex(from: json)
                        : HookNotificationContentResolver.claudeCode(from: json)
                    stdinSessionId = content.sessionId
                    subtitle = content.subtitle
                    resolvedMessage = content.message
                } catch let error as ExitCode {
                    throw error
                } catch {
                    fputs("Error: Invalid JSON on stdin: \(error.localizedDescription)\n", stderr)
                    throw ExitCode(1)
                }
            }

            // Resolve title: explicit --title wins, then appId, then "Growlrrr"
            let resolvedTitle = title ?? appId ?? "Growlrrr"

            let sessionId = HookSession.derive(
                environmentSessionId: ProcessInfo.processInfo.environment["GROWLRRR_SESSION_ID"],
                stdinSessionId: stdinSessionId,
                appId: appId)
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
                args += ["--appId", appId, resolvedMessage]

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
                message: resolvedMessage,
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

        @Option(
            name: .long,
            help: ArgumentHelp(
                "Command to consult before clearing; exit 0 clears, 1 leaves the notification alone, anything else clears with a warning",
                discussion: "Runs through /bin/sh -c with this command's stdin piped to it. Its stdout is diverted to stderr."))
        var gate: String?

        func run() async throws {
            // Claude Code pipes hook JSON on stdin; skip it when run from a
            // terminal so a manual invocation doesn't block waiting for EOF.
            var stdinData = Data()
            var stdinSessionId: String? = nil
            if isatty(STDIN_FILENO) == 0 {
                stdinData = FileHandle.standardInput.readDataToEndOfFile()
                if let json = try? JSONSerialization.jsonObject(with: stdinData) as? [String: Any] {
                    stdinSessionId = json["session_id"] as? String
                }
            }

            // The gate runs once, here; the --appId path below execs a plain
            // `clear` in the custom bundle and never sees --gate.
            if let gate, !Growlrrr.Hook.passesGate(gate, input: stdinData) {
                return
            }

            let sessionId = HookSession.derive(
                environmentSessionId: ProcessInfo.processInfo.environment["GROWLRRR_SESSION_ID"],
                stdinSessionId: stdinSessionId,
                appId: appId)

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
