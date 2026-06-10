import XCTest
import GrowlrrrCore

final class AppVersionTests: XCTestCase {

    func testResolveReadsShortVersionString() {
        XCTAssertEqual(
            AppVersion.resolve(infoDictionary: ["CFBundleShortVersionString": "1.4.1"]),
            "1.4.1")
    }

    func testResolveReturnsNilForMissingKey() {
        XCTAssertNil(AppVersion.resolve(infoDictionary: ["CFBundleVersion": "42"]))
    }

    func testResolveReturnsNilForNilDictionary() {
        XCTAssertNil(AppVersion.resolve(infoDictionary: nil))
    }

    func testCurrentNeverReturnsEmpty() {
        // In the test runner this resolves the xctest bundle's version; the
        // contract is just that something non-empty always comes back.
        XCTAssertFalse(AppVersion.current().isEmpty)
    }
}
