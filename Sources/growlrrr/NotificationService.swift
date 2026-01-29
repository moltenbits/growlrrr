import Foundation
import UniformTypeIdentifiers
import UserNotifications

actor NotificationService {
    private let center = UNUserNotificationCenter.current()
    private var delegate: NotificationDelegate?

    init() {}

    // MARK: - Authorization

    func requestAuthorization() async throws {
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional:
            // Already authorized
            return
        case .notDetermined:
            // First time - request permission
            let options: UNAuthorizationOptions = [.alert, .sound, .badge]
            let granted = try await center.requestAuthorization(options: options)
            guard granted else {
                throw GrowlrrrError.authorizationDenied
            }
        case .denied:
            throw GrowlrrrError.authorizationDenied
        case .ephemeral:
            // App Clips only - shouldn't happen for CLI
            return
        @unknown default:
            // Try to request anyway
            let options: UNAuthorizationOptions = [.alert, .sound, .badge]
            _ = try await center.requestAuthorization(options: options)
        }
    }

    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    func openNotificationSettings() async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["x-apple.systempreferences:com.apple.Notifications-Settings.extension"]
        try? process.run()
        process.waitUntilExit()
    }

    // MARK: - Sending Notifications

    func send(_ config: NotificationConfig) async throws -> String {
        let content = UNMutableNotificationContent()

        content.body = config.message

        if let title = config.title {
            content.title = title
        }

        if let subtitle = config.subtitle {
            content.subtitle = subtitle
        }

        switch config.sound {
        case .none:
            break
        case .default:
            content.sound = .default
        case .named(let name):
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: name))
        }

        if let threadId = config.threadId {
            content.threadIdentifier = threadId
        }

        if let category = config.category {
            content.categoryIdentifier = category
        }

        // Store URL in userInfo for later retrieval
        if let openUrl = config.open {
            content.userInfo["open"] = openUrl.absoluteString
        }

        // Store execute command in userInfo for later retrieval
        if let execute = config.execute {
            content.userInfo["execute"] = execute
        }

        // Attach image if provided
        if let imagePath = config.imagePath {
            let sourceUrl = URL(fileURLWithPath: imagePath)
            if FileManager.default.fileExists(atPath: imagePath) {
                do {
                    // UNNotificationAttachment MOVES the file, so we must copy to temp first
                    let tempDir = FileManager.default.temporaryDirectory
                        .appendingPathComponent("growlrrr-attachments", isDirectory: true)
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

                    let tempFile = tempDir.appendingPathComponent(UUID().uuidString + "-" + sourceUrl.lastPathComponent)
                    try FileManager.default.copyItem(at: sourceUrl, to: tempFile)

                    // Determine UTType from file extension
                    let typeHint: UTType = {
                        switch sourceUrl.pathExtension.lowercased() {
                        case "png": return .png
                        case "jpg", "jpeg": return .jpeg
                        case "gif": return .gif
                        case "heic": return .heic
                        default: return .png
                        }
                    }()

                    let attachment = try UNNotificationAttachment(
                        identifier: "icon",
                        url: tempFile,
                        options: [UNNotificationAttachmentOptionsTypeHintKey: typeHint.identifier]
                    )
                    content.attachments = [attachment]
                } catch {
                    fputs("Warning: Could not attach image: \(error.localizedDescription)\n", stderr)
                }
            } else {
                fputs("Warning: Image file not found: \(imagePath)\n", stderr)
            }
        }

        // Create request with no trigger (immediate delivery)
        let request = UNNotificationRequest(
            identifier: config.identifier,
            content: content,
            trigger: nil
        )

        try await center.add(request)

        return config.identifier
    }

    // MARK: - Wait for Delivery

    func waitForDelivery(identifier: String) async throws {
        // Poll until the notification appears in delivered notifications
        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline {
            // Yield to the main run loop to let the notification system process
            await MainActor.run {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            }
            let delivered = await center.deliveredNotifications()
            if delivered.contains(where: { $0.request.identifier == identifier }) {
                return
            }
        }
    }

    // MARK: - Wait for Interaction

    func waitForInteraction(identifier: String) async throws {
        // Set up delegate to capture interaction
        let delegate = NotificationDelegate()
        self.delegate = delegate
        center.delegate = delegate

        // Wait for interaction or timeout
        let result = await delegate.waitForNotification(identifier: identifier, timeout: 300)

        switch result {
        case .dismissed:
            // User dismissed or notification timed out
            break
        case .clicked(let urlToOpen):
            // Open the URL if present
            if let url = urlToOpen {
                try await openUrl(url)
            }
        case .action(let actionId, let urlToOpen):
            print("Action: \(actionId)")
            if let url = urlToOpen {
                try await openUrl(url)
            }
        case .timeout:
            throw GrowlrrrError.timeout
        }
    }

    private func openUrl(_ url: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.absoluteString]
        try process.run()
        process.waitUntilExit()
    }

    // MARK: - Listing Notifications

    func listPending() async -> [NotificationInfo] {
        let requests = await center.pendingNotificationRequests()
        return requests.map { request in
            NotificationInfo(
                identifier: request.identifier,
                title: request.content.title.isEmpty ? nil : request.content.title,
                body: request.content.body
            )
        }
    }

    func listDelivered() async -> [NotificationInfo] {
        let notifications = await center.deliveredNotifications()
        return notifications.map { notification in
            NotificationInfo(
                identifier: notification.request.identifier,
                title: notification.request.content.title.isEmpty ? nil : notification.request.content.title,
                body: notification.request.content.body
            )
        }
    }

    // MARK: - Clearing Notifications

    func clearPending(identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func clearDelivered(identifiers: [String]) async {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func clearAllPending() async {
        center.removeAllPendingNotificationRequests()
    }

    func clearAllDelivered() async {
        center.removeAllDeliveredNotifications()
    }

    func clearAll() async {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}

// MARK: - Notification Delegate

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let storage = ContinuationStorage()

    enum InteractionResult {
        case dismissed
        case clicked(URL?)
        case action(String, URL?)
        case timeout
    }

    func waitForNotification(identifier: String, timeout: TimeInterval) async -> InteractionResult {
        await withCheckedContinuation { continuation in
            Task {
                await storage.store(identifier: identifier, continuation: continuation)
            }

            // Set up timeout
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if let cont = await self.storage.remove(identifier: identifier) {
                    cont.resume(returning: .timeout)
                }
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        let userInfo = response.notification.request.content.userInfo
        let openUrl = (userInfo["open"] as? String).flatMap { URL(string: $0) }

        let result: InteractionResult
        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            result = .clicked(openUrl)
        case UNNotificationDismissActionIdentifier:
            result = .dismissed
        default:
            result = .action(response.actionIdentifier, openUrl)
        }

        Task {
            if let continuation = await self.storage.remove(identifier: identifier) {
                continuation.resume(returning: result)
            }
            completionHandler()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound])
    }
}

// MARK: - Actor-based Continuation Storage

private actor ContinuationStorage {
    private var continuations: [String: CheckedContinuation<NotificationDelegate.InteractionResult, Never>] = [:]

    func store(identifier: String, continuation: CheckedContinuation<NotificationDelegate.InteractionResult, Never>) {
        continuations[identifier] = continuation
    }

    func remove(identifier: String) -> CheckedContinuation<NotificationDelegate.InteractionResult, Never>? {
        continuations.removeValue(forKey: identifier)
    }
}
