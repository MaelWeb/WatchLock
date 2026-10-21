import XCTest
@testable import WatchLock

final class DeveloperModeTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "DeveloperModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testOffByDefault() {
        XCTAssertFalse(DeveloperMode.resolve(environment: [:], defaults: makeDefaults()))
    }

    func testEnvironmentVariableEnables() {
        XCTAssertTrue(DeveloperMode.resolve(environment: ["WATCHLOCK_DEVELOPER": "1"], defaults: makeDefaults()))
        XCTAssertFalse(DeveloperMode.resolve(environment: ["WATCHLOCK_DEVELOPER": "0"], defaults: makeDefaults()))
    }

    func testDefaultsKeyEnables() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: DeveloperMode.defaultsKey)
        XCTAssertTrue(DeveloperMode.resolve(environment: [:], defaults: defaults))
    }
}
