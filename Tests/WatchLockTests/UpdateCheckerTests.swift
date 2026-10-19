import XCTest
@testable import WatchLock

final class UpdateCheckerTests: XCTestCase {
    func testVersionFromTagURL() {
        let url = URL(string: "https://github.com/MaelWeb/WatchLock/releases/tag/v1.2.3")!
        XCTAssertEqual(UpdateChecker.version(fromRedirected: url), "1.2.3")
        XCTAssertEqual(UpdateChecker.version(fromRedirected: URL(string: "https://github.com/x/y/releases/tag/2.0")!), "2.0")
    }

    func testNonTagURLsYieldNoVersion() {
        XCTAssertNil(UpdateChecker.version(fromRedirected: URL(string: "https://github.com/MaelWeb/WatchLock/releases")!))
        XCTAssertNil(UpdateChecker.version(fromRedirected: URL(string: "https://github.com/MaelWeb/WatchLock/releases/tag/nightly")!))
    }

    func testIsNewer() {
        XCTAssertTrue(UpdateChecker.isNewer("1.0.1", than: "1.0.0"))
        XCTAssertTrue(UpdateChecker.isNewer("1.10.0", than: "1.9.9"))
        XCTAssertTrue(UpdateChecker.isNewer("2", than: "1.9"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0.0", than: "1.0.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0", than: "1.0.0"))
        XCTAssertFalse(UpdateChecker.isNewer("0.9.9", than: "1.0.0"))
    }

    func testUnparseableVersionsNeverPromptUpdate() {
        XCTAssertFalse(UpdateChecker.isNewer("abc", than: "1.0.0"))
        XCTAssertFalse(UpdateChecker.isNewer("2.0.0", than: "—"))
    }

    func testPrereleaseSuffixIgnoredForComparison() {
        XCTAssertTrue(UpdateChecker.isNewer("1.1.0-beta.1", than: "1.0.0"))
    }

    func testOutcomeMapping() {
        let tag = URL(string: "https://github.com/MaelWeb/WatchLock/releases/tag/v1.1.0")!
        XCTAssertEqual(
            UpdateChecker.outcome(finalURL: tag, current: "1.0.0"),
            .available(latest: "1.1.0", current: "1.0.0", page: tag)
        )
        XCTAssertEqual(UpdateChecker.outcome(finalURL: tag, current: "1.1.0"), .upToDate(current: "1.1.0"))
        XCTAssertEqual(UpdateChecker.outcome(finalURL: UpdateChecker.releasesURL, current: "1.0.0"), .noRelease)
        if case .failed = UpdateChecker.outcome(finalURL: nil, current: "1.0.0") {} else { XCTFail("nil URL 应为失败") }
    }

    func testHelpURLFollowsLanguage() {
        XCTAssertTrue(UpdateChecker.helpURL(preferredLanguages: ["zh-Hans-CN"]).absoluteString.hasSuffix("docs/help.md"))
        XCTAssertTrue(UpdateChecker.helpURL(preferredLanguages: ["en-US"]).absoluteString.hasSuffix("docs/help.en.md"))
        XCTAssertTrue(UpdateChecker.helpURL(preferredLanguages: []).absoluteString.hasSuffix("docs/help.en.md"))
    }
}
