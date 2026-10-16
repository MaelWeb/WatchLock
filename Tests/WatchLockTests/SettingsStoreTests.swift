import XCTest
@testable import WatchLock

/// 设置与暂停逻辑（FR-06）。使用独立 UserDefaults suite，避免污染真实设置。
final class SettingsStoreTests: XCTestCase {
    private var suiteName: String = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "watchlock.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    func testMenuBarShowsIconOnlyByDefault() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.showRSSIInMenuBar, "菜单栏默认只显示图标，状态文字需用户主动开启")

        // 用户主动开启后会被持久化，重新加载仍然保持开启。
        store.showRSSIInMenuBar = true
        XCTAssertTrue(SettingsStore(defaults: defaults).showRSSIInMenuBar)
    }

    func testPauseAndExpiry() {
        let store = SettingsStore(defaults: defaults)
        let now = Date()
        XCTAssertFalse(store.isPaused(now: now))

        store.pause(minutes: 15)
        XCTAssertTrue(store.isPaused(now: now))
        XCTAssertFalse(store.isPaused(now: now.addingTimeInterval(16 * 60)))

        store.resume()
        XCTAssertFalse(store.isPaused(now: now))
    }

    func testProximityConfigIsDerivedFromSettings() {
        let store = SettingsStore(defaults: defaults)
        store.nearRSSI = -50
        store.farRSSI = -68
        store.farDwell = 8
        store.smoothing = 0.4

        let config = store.proximityConfig
        XCTAssertEqual(config.nearRSSI, -50)
        XCTAssertEqual(config.farRSSI, -68)
        XCTAssertEqual(config.farDwell, 8)
        XCTAssertEqual(config.smoothing, 0.4)
    }

    func testSettingsArePersisted() {
        let store = SettingsStore(defaults: defaults)
        store.nearRSSI = -48
        store.lockMethod = .displaySleep

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.nearRSSI, -48)
        XCTAssertEqual(reloaded.lockMethod, .displaySleep)
    }

    func testBindingAdvertisementFingerprintIsPersisted() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertNil(store.boundWatchAdvertisement)

        store.boundWatchAdvertisement = "type=0x10/len=11"
        XCTAssertEqual(SettingsStore(defaults: defaults).boundWatchAdvertisement, "type=0x10/len=11")
    }

    func testDefaultValues() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.isEnabled)
        XCTAssertEqual(store.nearRSSI, -55)
        XCTAssertEqual(store.farRSSI, -70)
        XCTAssertEqual(store.smoothing, 0.25, accuracy: .ulpOfOne)
        XCTAssertEqual(store.farDwell, 5, accuracy: .ulpOfOne)
        XCTAssertEqual(store.signalLostTimeout, 20, accuracy: .ulpOfOne)
        XCTAssertTrue(store.lockOnSignalLoss)
        XCTAssertEqual(store.unlockGraceAfterWake, 8, accuracy: .ulpOfOne)
        XCTAssertEqual(store.lockMethod, .controlCommandQ)
        XCTAssertFalse(store.debugMenuEnabled)
        XCTAssertFalse(store.hasCompletedOnboarding)
    }
}
