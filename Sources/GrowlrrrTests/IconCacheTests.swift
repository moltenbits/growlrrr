import XCTest
import GrowlrrrCore

final class IconCacheTests: XCTestCase {

    private var tempBundle: URL!

    override func setUpWithError() throws {
        tempBundle = FileManager.default.temporaryDirectory
            .appendingPathComponent("growlrrr-icon-cache-\(UUID().uuidString).app")
        try FileManager.default.createDirectory(at: tempBundle, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempBundle)
    }

    private func modificationDate(of url: URL) throws -> Date {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.modificationDate] as? Date)
    }

    // MARK: - touchBundle

    func testTouchBundleAdvancesModificationDate() throws {
        let stale = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes([.modificationDate: stale], ofItemAtPath: tempBundle.path)
        XCTAssertEqual(try modificationDate(of: tempBundle), stale)

        try IconCache.touchBundle(at: tempBundle)

        let touched = try modificationDate(of: tempBundle)
        XCTAssertGreaterThan(touched, stale)
        XCTAssertEqual(touched.timeIntervalSinceNow, 0, accuracy: 5)
    }

    /// Writing a new icon only changes files nested inside the bundle, which
    /// leaves the bundle's own mtime — the cache key — untouched. This is the
    /// exact condition that made changed icons appear stale.
    func testNestedWriteLeavesBundleDateStaleUntilTouched() throws {
        let stale = Date(timeIntervalSince1970: 1_000_000)
        let resources = tempBundle
            .appendingPathComponent("Contents")
            .appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: stale], ofItemAtPath: tempBundle.path)

        try Data("icns".utf8).write(to: resources.appendingPathComponent("AppIcon.icns"))
        XCTAssertEqual(try modificationDate(of: tempBundle), stale, "nested write must not move the bundle mtime")

        try IconCache.touchBundle(at: tempBundle)
        XCTAssertGreaterThan(try modificationDate(of: tempBundle), stale)
    }

    func testTouchBundleThrowsWhenBundleMissing() {
        let missing = tempBundle.appendingPathComponent("Nope.app")
        XCTAssertThrowsError(try IconCache.touchBundle(at: missing))
    }

    // MARK: - Services

    /// growlrrr bundles are LSUIElement agents that never appear in the Dock,
    /// so restarting it would be user-visible churn for no benefit.
    func testNotificationServicesExcludeDock() {
        XCTAssertFalse(IconCache.notificationServices.contains("Dock"))
        XCTAssertFalse(IconCache.notificationServices.contains("Finder"))
    }

    func testNotificationServicesCoverNotificationDaemons() {
        XCTAssertTrue(IconCache.notificationServices.contains("usernoted"))
        XCTAssertTrue(IconCache.notificationServices.contains("NotificationCenter"))
    }
}
