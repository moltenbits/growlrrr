import XCTest
import GrowlrrrCore

final class T3CodeThreadTests: XCTestCase {

    /// The shape `t3 thread show <id> --json` prints, trimmed to the fields
    /// that matter here.
    private func threadShowOutput(link: String, title: Any? = "Clean Up Branches Merged to Main") -> Data {
        var thread: [String: Any] = [
            "threadId": "962887c7-9d48-4440-99bd-0461933b8033",
            "link": link,
        ]
        thread["title"] = title
        let json: [String: Any] = ["thread": thread, "messages": []]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    private func thread(link: String) -> T3CodeThread? {
        T3CodeThread(threadShowOutput: threadShowOutput(link: link))
    }

    /// The Info.plist Safari writes for an "Add to Dock" web app, trimmed to
    /// the manifest.
    private func webAppInfoPlist(startURL: String?) -> Data {
        var manifest: [String: Any] = ["display": "standalone", "name": "T3 Code"]
        if let startURL {
            manifest["start_url"] = startURL
        }
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.apple.Safari.WebApp.4572742D-AA93-42CB-AD8E-43A4DD2B164A",
            "Manifest": manifest,
        ]
        return try! PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    }

    // MARK: - Parsing `t3 thread show`

    func testReadsTheThreadIdAndOriginFromTheHostedLink() throws {
        let thread = try XCTUnwrap(thread(
            link: "https://app.t3.codes/threads/7e9a75d0-3c28-48ef-a9f3-9551e82938b6/962887c7-9d48-4440-99bd-0461933b8033"))
        XCTAssertEqual(thread.threadId, "962887c7-9d48-4440-99bd-0461933b8033")
        XCTAssertEqual(thread.origin, "https://app.t3.codes")
    }

    func testReadsTheThreadTitle() throws {
        let thread = try XCTUnwrap(thread(link: "https://app.t3.codes/threads/env-1/thread-1"))
        XCTAssertEqual(thread.title, "Clean Up Branches Merged to Main")
    }

    func testAThreadWithoutAUsableTitleIsStillAThread() throws {
        for title in [nil, "", "  \n ", 42] as [Any?] {
            let thread = try XCTUnwrap(T3CodeThread(threadShowOutput: threadShowOutput(
                link: "https://app.t3.codes/threads/env-1/thread-1", title: title)))
            XCTAssertNil(thread.title)
            XCTAssertEqual(thread.threadId, "thread-1")
        }
    }

    func testATitleIsKeptOnOneLine() throws {
        let thread = try XCTUnwrap(T3CodeThread(threadShowOutput: threadShowOutput(
            link: "https://app.t3.codes/threads/env-1/thread-1", title: "  Fix the\nlogin page ")))
        XCTAssertEqual(thread.title, "Fix the login page")
    }

    func testKeepsAnExplicitPortInTheOrigin() throws {
        let thread = try XCTUnwrap(thread(link: "http://localhost:3773/threads/env-1/thread-1"))
        XCTAssertEqual(thread.origin, "http://localhost:3773")
    }

    func testRejectsOutputThatIsNotJSON() {
        XCTAssertNil(T3CodeThread(threadShowOutput: Data()))
        XCTAssertNil(T3CodeThread(threadShowOutput: Data("Thread not found".utf8)))
    }

    func testRejectsOutputWithoutALink() {
        let json: [String: Any] = ["thread": ["threadId": "thread-1"], "messages": []]
        let output = try! JSONSerialization.data(withJSONObject: json)
        XCTAssertNil(T3CodeThread(threadShowOutput: output))
    }

    func testRejectsLinksThatDoNotNameAThread() {
        // Only /threads/<environment>/<thread> identifies a thread.
        XCTAssertNil(thread(link: "https://app.t3.codes/new"))
        XCTAssertNil(thread(link: "https://app.t3.codes/threads/env-1"))
        XCTAssertNil(thread(link: "https://app.t3.codes/threads/env-1/thread-1/extra"))
        XCTAssertNil(thread(link: "https://app.t3.codes/settings/env-1/thread-1"))
    }

    func testRejectsLinksThatAreNotWebLinks() {
        XCTAssertNil(thread(link: "file:///threads/env-1/thread-1"))
        XCTAssertNil(thread(link: "/threads/env-1/thread-1"))
    }

    func testRejectsUnexpectedCharacters() {
        // The link ends up in a command executed via `sh -c`, so ids and
        // hosts outside their plain alphabets are refused rather than quoted.
        XCTAssertNil(thread(link: "https://app.t3.codes/threads/env-1/thread'; rm -rf ~'"))
        XCTAssertNil(thread(link: "https://app.t3.codes/threads/env 1/thread-1"))
        XCTAssertNil(thread(link: "https://app.t3.codes/threads/env-1/thread-1&x=y"))
        XCTAssertNil(thread(link: "https://app.t3'.codes/threads/env-1/thread-1"))
    }

    // MARK: - Commands

    func testDesktopAppRevealCommandUsesTheDesktopScheme() throws {
        // The CLI prints the hosted web link; the desktop app answers the
        // same environment/thread path under its own t3code: scheme.
        let thread = try XCTUnwrap(thread(
            link: "https://app.t3.codes/threads/7e9a75d0-3c28-48ef-a9f3-9551e82938b6/962887c7-9d48-4440-99bd-0461933b8033"))
        XCTAssertEqual(
            thread.desktopAppRevealCommand,
            "open 't3code://threads/7e9a75d0-3c28-48ef-a9f3-9551e82938b6/962887c7-9d48-4440-99bd-0461933b8033'")
    }

    func testDesktopAppRevealCommandDropsATrailingSlash() throws {
        let thread = try XCTUnwrap(thread(link: "https://app.t3.codes/threads/env-1/thread-1/"))
        XCTAssertEqual(thread.desktopAppRevealCommand, "open 't3code://threads/env-1/thread-1'")
    }

    func testWebAppRevealCommandOpensTheHostedLinkInThatApp() throws {
        let thread = try XCTUnwrap(thread(link: "https://app.t3.codes/threads/env-1/thread-1"))
        XCTAssertEqual(
            thread.webAppRevealCommand(appPath: "/Users/me/Applications/T3 Code (Growlrrr).app"),
            "open -a '/Users/me/Applications/T3 Code (Growlrrr).app' 'https://app.t3.codes/threads/env-1/thread-1'")
    }

    func testWebAppRevealCommandQuotesAnApostropheInTheAppPath() throws {
        let thread = try XCTUnwrap(thread(link: "https://app.t3.codes/threads/env-1/thread-1"))
        XCTAssertEqual(
            thread.webAppRevealCommand(appPath: "/Users/me/Applications/Sam's T3.app"),
            #"open -a '/Users/me/Applications/Sam'\''s T3.app' 'https://app.t3.codes/threads/env-1/thread-1'"#)
    }

    // MARK: - Recognising a web app of the same site

    func testWebAppOriginComesFromTheManifestStartURL() {
        XCTAssertEqual(
            T3CodeThread.webAppOrigin(infoPlist: webAppInfoPlist(startURL: "https://app.t3.codes/")),
            "https://app.t3.codes")
        XCTAssertEqual(
            T3CodeThread.webAppOrigin(infoPlist: webAppInfoPlist(startURL: "https://web.whatsapp.com/")),
            "https://web.whatsapp.com")
    }

    func testWebAppOriginIgnoresHostCase() {
        XCTAssertEqual(
            T3CodeThread.webAppOrigin(infoPlist: webAppInfoPlist(startURL: "https://App.T3.Codes/")),
            "https://app.t3.codes")
    }

    func testAnAppWithoutAWebManifestHasNoWebAppOrigin() {
        let plist: [String: Any] = ["CFBundleIdentifier": "com.tinyspeck.slackmacgap"]
        let ordinaryApp = try! PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0)
        XCTAssertNil(T3CodeThread.webAppOrigin(infoPlist: ordinaryApp))
        XCTAssertNil(T3CodeThread.webAppOrigin(infoPlist: webAppInfoPlist(startURL: nil)))
        XCTAssertNil(T3CodeThread.webAppOrigin(infoPlist: Data("not a plist".utf8)))
    }
}
