import Foundation

// MARK: - Notification Configuration

public struct NotificationConfig {
    public let message: String
    public let title: String?
    public let subtitle: String?
    public let sound: SoundOption
    public let imagePath: String?
    public let open: URL?
    public let execute: String?
    public let identifier: String
    public let threadId: String?
    public let category: String?

    public init(
        message: String,
        title: String?,
        subtitle: String?,
        sound: SoundOption,
        imagePath: String?,
        open: URL?,
        execute: String?,
        identifier: String,
        threadId: String?,
        category: String?
    ) {
        self.message = message
        self.title = title
        self.subtitle = subtitle
        self.sound = sound
        self.imagePath = imagePath
        self.open = open
        self.execute = execute
        self.identifier = identifier
        self.threadId = threadId
        self.category = category
    }
}

// MARK: - Sound Options

public enum SoundOption: Equatable {
    case none
    case `default`
    case named(String)

    public static func from(_ string: String?) -> SoundOption {
        guard let string = string?.lowercased() else {
            return .default
        }

        switch string {
        case "none", "silent":
            return .none
        case "default":
            return .default
        default:
            return .named(string)
        }
    }
}

// MARK: - Notification Info (for listing)

public struct NotificationInfo: Codable {
    public let identifier: String
    public let title: String?
    public let body: String
    public var app: String?

    enum CodingKeys: String, CodingKey {
        case identifier, title, body, app
    }

    public init(identifier: String, title: String?, body: String, app: String? = nil) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.app = app
    }
}

// MARK: - Errors

public enum GrowlrrrError: Error, LocalizedError, CustomStringConvertible {
    case authorizationDenied
    case notificationFailed(String)
    case timeout
    case invalidUrl(String)
    case customAppNotFound(String)

    public var description: String {
        switch self {
        case .authorizationDenied:
            return "Notification permission denied. Please enable notifications in System Settings > Notifications."
        case .notificationFailed(let reason):
            return reason
        case .timeout:
            return "Notification interaction timed out"
        case .invalidUrl(let url):
            return "Invalid URL: \(url)"
        case .customAppNotFound(let name):
            return "Custom app '\(name)' does not exist. Create it with: grrr apps add --appId \(name) --appIcon <path>"
        }
    }

    public var errorDescription: String? {
        return description
    }
}
