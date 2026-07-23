import XCTest
import GrowlrrrCore

final class IconSourceTests: XCTestCase {

    private var bundle: URL!
    private var plist: URL!

    override func setUpWithError() throws {
        bundle = FileManager.default.temporaryDirectory
            .appendingPathComponent("growlrrr-icon-source-\(UUID().uuidString).app")
        plist = bundle.appendingPathComponent("Contents").appendingPathComponent("Info.plist")

        try FileManager.default.createDirectory(
            at: plist.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try writePlist(["CFBundleIdentifier": "com.moltenbits.growlrrr.Test", "CFBundleName": "Test"])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: bundle)
    }

    private func writePlist(_ contents: [String: Any]) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: contents, format: .xml, options: 0)
        try data.write(to: plist)
    }

    private func readPlist() throws -> [String: Any] {
        try XCTUnwrap(NSDictionary(contentsOf: plist) as? [String: Any])
    }

    /// Creates a real file so a recorded path resolves as still present.
    private func makeIconFile(named name: String = "icon.png") throws -> URL {
        let url = bundle.appendingPathComponent(name)
        try Data("png".utf8).write(to: url)
        return url
    }

    // MARK: - Reading

    func testIconSourceIsNotRecordedWhenKeyAbsent() {
        XCTAssertEqual(CustomAppBundle.iconSource(at: bundle), .notRecorded)
    }

    func testIconSourceIsNotRecordedWhenBundleMissing() {
        let missing = bundle.appendingPathComponent("Nope.app")
        XCTAssertEqual(CustomAppBundle.iconSource(at: missing), .notRecorded)
    }

    func testIconSourceRoundTripsRecordedPath() throws {
        let icon = try makeIconFile()
        try CustomAppBundle.recordIconSource(icon.path, at: bundle)

        XCTAssertEqual(CustomAppBundle.iconSource(at: bundle), .recorded(icon.path))
    }

    /// The whole point of showing the icon is spotting one that moved away.
    func testIconSourceReportsMissingWhenFileIsGone() throws {
        let icon = try makeIconFile()
        try CustomAppBundle.recordIconSource(icon.path, at: bundle)
        try FileManager.default.removeItem(at: icon)

        XCTAssertEqual(CustomAppBundle.iconSource(at: bundle), .missing(icon.path))
    }

    // MARK: - Writing

    func testRecordIconSourcePreservesExistingPlistKeys() throws {
        let icon = try makeIconFile()
        try CustomAppBundle.recordIconSource(icon.path, at: bundle)

        let contents = try readPlist()
        XCTAssertEqual(contents["CFBundleIdentifier"] as? String, "com.moltenbits.growlrrr.Test")
        XCTAssertEqual(contents["CFBundleName"] as? String, "Test")
    }

    func testRecordIconSourceOverwritesPreviousValue() throws {
        let first = try makeIconFile(named: "first.png")
        let second = try makeIconFile(named: "second.png")

        try CustomAppBundle.recordIconSource(first.path, at: bundle)
        try CustomAppBundle.recordIconSource(second.path, at: bundle)

        XCTAssertEqual(CustomAppBundle.iconSource(at: bundle), .recorded(second.path))
    }

    /// A relative path is meaningless once the working directory changes.
    func testRecordIconSourceStoresAbsolutePath() throws {
        try CustomAppBundle.recordIconSource("./relative/icon.png", at: bundle)

        let stored = try XCTUnwrap(CustomAppBundle.iconSource(at: bundle).path)
        XCTAssertTrue(stored.hasPrefix("/"), "expected an absolute path, got \(stored)")
        XCTAssertTrue(stored.hasSuffix("relative/icon.png"))
    }

    func testRecordIconSourceThrowsWhenPlistMissing() {
        let missing = bundle.appendingPathComponent("Nope.app")
        XCTAssertThrowsError(try CustomAppBundle.recordIconSource("/tmp/icon.png", at: missing))
    }

    // MARK: - Path accessor

    func testPathAccessor() {
        XCTAssertEqual(CustomAppBundle.IconSource.recorded("/a/icon.png").path, "/a/icon.png")
        XCTAssertEqual(CustomAppBundle.IconSource.missing("/b/icon.png").path, "/b/icon.png")
        XCTAssertNil(CustomAppBundle.IconSource.notRecorded.path)
    }
}
