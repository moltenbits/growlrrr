import XCTest
import GrowlrrrCore

final class GrowlrrrTests: XCTestCase {

    // MARK: - SoundOption Tests

    func testSoundOptionFromNil() {
        XCTAssertEqual(SoundOption.from(nil), .default)
    }

    func testSoundOptionFromNone() {
        XCTAssertEqual(SoundOption.from("none"), .none)
        XCTAssertEqual(SoundOption.from("silent"), .none)
        XCTAssertEqual(SoundOption.from("NONE"), .none)
        XCTAssertEqual(SoundOption.from("Silent"), .none)
    }

    func testSoundOptionFromDefault() {
        XCTAssertEqual(SoundOption.from("default"), .default)
        XCTAssertEqual(SoundOption.from("DEFAULT"), .default)
    }

    func testSoundOptionFromNamed() {
        XCTAssertEqual(SoundOption.from("Ping"), .named("ping"))
        XCTAssertEqual(SoundOption.from("Basso"), .named("basso"))
        XCTAssertEqual(SoundOption.from("Custom Sound"), .named("custom sound"))
    }

    // MARK: - NotificationConfig Tests

    func testNotificationConfigWithAllFields() {
        let config = NotificationConfig(
            message: "Test message",
            title: "Test Title",
            subtitle: "Test Subtitle",
            sound: .default,
            imagePath: "/path/to/image.png",
            open: URL(string: "https://example.com"),
            execute: "echo hello",
            identifier: "test-id",
            threadId: "thread-123",
            category: "category-1"
        )

        XCTAssertEqual(config.message, "Test message")
        XCTAssertEqual(config.title, "Test Title")
        XCTAssertEqual(config.subtitle, "Test Subtitle")
        XCTAssertEqual(config.sound, .default)
        XCTAssertEqual(config.imagePath, "/path/to/image.png")
        XCTAssertEqual(config.open?.absoluteString, "https://example.com")
        XCTAssertEqual(config.execute, "echo hello")
        XCTAssertEqual(config.identifier, "test-id")
        XCTAssertEqual(config.threadId, "thread-123")
        XCTAssertEqual(config.category, "category-1")
    }

    func testNotificationConfigWithMinimalFields() {
        let config = NotificationConfig(
            message: "Just a message",
            title: nil,
            subtitle: nil,
            sound: .none,
            imagePath: nil,
            open: nil,
            execute: nil,
            identifier: "minimal-id",
            threadId: nil,
            category: nil
        )

        XCTAssertEqual(config.message, "Just a message")
        XCTAssertNil(config.title)
        XCTAssertNil(config.subtitle)
        XCTAssertEqual(config.sound, .none)
        XCTAssertNil(config.imagePath)
        XCTAssertNil(config.open)
        XCTAssertNil(config.execute)
        XCTAssertEqual(config.identifier, "minimal-id")
        XCTAssertNil(config.threadId)
        XCTAssertNil(config.category)
    }

    // MARK: - NotificationInfo Tests

    func testNotificationInfoCoding() throws {
        let info = NotificationInfo(
            identifier: "notif-123",
            title: "Test Title",
            body: "Test Body",
            app: "TestApp"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(info)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(NotificationInfo.self, from: data)

        XCTAssertEqual(decoded.identifier, "notif-123")
        XCTAssertEqual(decoded.title, "Test Title")
        XCTAssertEqual(decoded.body, "Test Body")
        XCTAssertEqual(decoded.app, "TestApp")
    }

    func testNotificationInfoWithNilTitle() throws {
        let info = NotificationInfo(
            identifier: "notif-456",
            title: nil,
            body: "Body only"
        )

        XCTAssertEqual(info.identifier, "notif-456")
        XCTAssertNil(info.title)
        XCTAssertEqual(info.body, "Body only")
        XCTAssertNil(info.app)
    }

    // MARK: - GrowlrrrError Tests

    func testErrorDescriptions() {
        XCTAssertTrue(GrowlrrrError.authorizationDenied.description.contains("permission denied"))

        let failedError = GrowlrrrError.notificationFailed("Something went wrong")
        XCTAssertEqual(failedError.description, "Something went wrong")

        XCTAssertTrue(GrowlrrrError.timeout.description.contains("timed out"))

        let urlError = GrowlrrrError.invalidUrl("not-a-url")
        XCTAssertTrue(urlError.description.contains("not-a-url"))

        let appError = GrowlrrrError.customAppNotFound("MyApp")
        XCTAssertTrue(appError.description.contains("MyApp"))
        XCTAssertTrue(appError.description.contains("does not exist"))
    }

    func testErrorLocalizedDescription() {
        let error = GrowlrrrError.authorizationDenied
        XCTAssertEqual(error.errorDescription, error.description)
    }

    // MARK: - CustomAppBundle Tests

    func testBundleIdentifier() {
        let identifier = CustomAppBundle.bundleIdentifier(forAppName: "TestApp")
        XCTAssertEqual(identifier, "com.moltenbits.growlrrr.TestApp")
    }

    func testBundlePath() {
        let path = CustomAppBundle.bundlePath(forAppName: "TestApp")
        XCTAssertTrue(path.path.contains(".growlrrr/apps/TestApp.app"))
    }

    func testExecutablePath() {
        let path = CustomAppBundle.executablePath(forAppName: "TestApp")
        XCTAssertTrue(path.path.contains("TestApp.app/Contents/MacOS/growlrrr"))
    }

    func testListCustomApps() {
        // This test verifies the function runs without crashing
        // The actual result depends on the system state
        let apps = CustomAppBundle.listCustomApps()
        // Result is an array of strings (may be empty or contain existing custom apps)
        XCTAssertNotNil(apps)
    }

    func testIsRunningFromCustomApp() {
        // When running tests, we should not be in a custom app bundle
        XCTAssertFalse(CustomAppBundle.isRunningFromCustomApp())
    }

    func testCurrentCustomAppName() {
        // When running tests, we should not be in a custom app bundle
        XCTAssertNil(CustomAppBundle.currentCustomAppName())
    }
}
