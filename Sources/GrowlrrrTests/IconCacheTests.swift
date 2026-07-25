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

    // MARK: - Icon store discovery

    private func makeDirs(_ relativePaths: [String], under root: URL) throws {
        for path in relativePaths {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(path),
                withIntermediateDirectories: true
            )
        }
    }

    func testIconStorePathsFindsStoresInCacheDirectories() throws {
        try makeDirs(
            [
                "dc/4r9xabc/C/com.apple.iconservicesagent",
                "dc/4r9xabc/C/com.apple.iconservices",
            ],
            under: tempBundle
        )

        let found = IconCache.iconStorePaths(under: tempBundle).map(\.lastPathComponent).sorted()
        XCTAssertEqual(found, ["com.apple.iconservices", "com.apple.iconservicesagent"])
    }

    /// The T/ sibling of the C/ cache directory is the agent's live temp
    /// directory — deleting it out from under the running agent is not the
    /// proven recipe and must never happen.
    func testIconStorePathsIgnoresTempDirectories() throws {
        try makeDirs(
            [
                "dc/4r9xabc/T/com.apple.iconservicesagent",
                "dc/4r9xabc/C/unrelated-directory",
            ],
            under: tempBundle
        )

        XCTAssertEqual(IconCache.iconStorePaths(under: tempBundle), [])
    }

    func testIconStorePathsHonorsDepthLimit() throws {
        try makeDirs(["a/b/c/d/e/C/com.apple.iconservices"], under: tempBundle)

        XCTAssertEqual(IconCache.iconStorePaths(under: tempBundle), [])
    }

    func testFlushIconStoresRemovesStoresAndLeavesTempAlone() throws {
        try makeDirs(
            [
                "dc/4r9xabc/C/com.apple.iconservicesagent/store-contents",
                "dc/4r9xabc/T/com.apple.iconservicesagent",
            ],
            under: tempBundle
        )

        let removed = IconCache.flushIconStores(under: tempBundle)

        XCTAssertEqual(removed.map(\.lastPathComponent), ["com.apple.iconservicesagent"])
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: tempBundle.appendingPathComponent("dc/4r9xabc/C/com.apple.iconservicesagent").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: tempBundle.appendingPathComponent("dc/4r9xabc/T/com.apple.iconservicesagent").path
            )
        )
    }
}
