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

    // MARK: - 信任场所 / 辅助设备

    func testTrustedPlacePausesIndependentlyOfManualPause() {
        let store = SettingsStore(defaults: defaults)
        let now = Date()
        XCTAssertFalse(store.isPaused(now: now))

        store.activeTrustedPlaceName = "家"
        XCTAssertTrue(store.isPaused(now: now))
        XCTAssertFalse(store.isManuallyPaused(now: now), "信任场所不能被当成手动暂停")

        // 手动暂停到期不会因为信任场所而被延长，反之亦然。
        store.pause(minutes: 15)
        store.activeTrustedPlaceName = nil
        XCTAssertTrue(store.isPaused(now: now))
        XCTAssertFalse(store.isPaused(now: now.addingTimeInterval(16 * 60)))
    }

    func testTrustedPlaceDisabledOrOverriddenDoesNotPause() {
        let store = SettingsStore(defaults: defaults)
        store.activeTrustedPlaceName = "家"
        store.trustedPlaceEnabled = false
        XCTAssertFalse(store.isPaused)

        store.trustedPlaceEnabled = true
        XCTAssertTrue(store.isPaused)
        store.trustedPlaceOverridden = true
        XCTAssertFalse(store.isPaused, "用户点了恢复后，离开该场所之前不再按场所暂停")
    }

    func testActivePlaceIsRuntimeOnly() {
        let store = SettingsStore(defaults: defaults)
        store.activeTrustedPlaceName = "家"
        store.trustedPlaceOverridden = true
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertNil(reloaded.activeTrustedPlaceName, "运行时状态不能落盘，否则重启后会在不在场所时仍然暂停")
        XCTAssertFalse(reloaded.trustedPlaceOverridden)
        XCTAssertFalse(reloaded.isPaused)
    }

    func testTrustedPlacesAndAuxiliaryDevicesPersist() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.trustedPlaces.isEmpty)
        XCTAssertTrue(store.auxiliaryDevices.isEmpty)
        XCTAssertTrue(store.trustedPlaceEnabled)
        XCTAssertTrue(store.fusionEnabled)

        let place = TrustedPlace.Place(name: "家", gatewayMAC: "aa:bb:cc:dd:ee:01", ssid: "Home")
        store.trustedPlaces = [place]
        store.auxiliaryDevices = [AuxiliaryDevice(id: "x", name: "iPhone", advertisement: "type=0x10")]

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.trustedPlaces, [place])
        XCTAssertEqual(reloaded.auxiliaryDevices.map(\.name), ["iPhone"])
    }

    func testCorruptedStoredDataFallsBackToEmpty() {
        defaults.set(Data([0x01, 0x02]), forKey: "settings.trustedPlaces")
        defaults.set(Data([0xff]), forKey: "settings.auxiliaryDevices")
        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.trustedPlaces.isEmpty)
        XCTAssertTrue(store.auxiliaryDevices.isEmpty)
    }

    func testFusionConfigNeedsDevicesToBeEnabled() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.fusionConfig.enabled, "没选任何辅助设备时不应启用")
        store.auxiliaryDevices = [AuxiliaryDevice(id: "x", name: "iPhone", advertisement: nil)]
        XCTAssertTrue(store.fusionConfig.enabled)
        store.fusionEnabled = false
        XCTAssertFalse(store.fusionConfig.enabled)
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
        XCTAssertFalse(store.hasCompletedOnboarding)
    }

    // MARK: - 设备手动覆盖

    func testDeviceOverridePersistsAndClearsWhenEmpty() {
        let store = SettingsStore(defaults: defaults)
        store.setDeviceOverride(DeviceOverride(name: "  老王的手机  ", kind: .iPhone), for: "id-1")

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.deviceOverrides["id-1"], DeviceOverride(name: "老王的手机", kind: .iPhone))

        reloaded.setDeviceOverride(DeviceOverride(name: " ", kind: nil), for: "id-1")
        XCTAssertNil(reloaded.deviceOverrides["id-1"], "名称与图标都为空应视为清除")
        reloaded.setDeviceOverride(DeviceOverride(name: "x", kind: nil), for: "id-2")
        reloaded.setDeviceOverride(nil, for: "id-2")
        XCTAssertTrue(reloaded.deviceOverrides.isEmpty)
    }

    func testMoveDeviceOverrideFollowsAddressRotation() {
        let store = SettingsStore(defaults: defaults)
        store.setDeviceOverride(DeviceOverride(name: "旧", kind: nil), for: "old")
        store.moveDeviceOverride(from: "old", to: "new")

        XCTAssertNil(store.deviceOverrides["old"])
        XCTAssertEqual(store.deviceOverrides["new"]?.name, "旧")
    }

    func testMoveDeviceOverrideKeepsExistingOverrideOnTarget() {
        let store = SettingsStore(defaults: defaults)
        store.setDeviceOverride(DeviceOverride(name: "旧", kind: nil), for: "old")
        store.setDeviceOverride(DeviceOverride(name: "新", kind: nil), for: "new")
        store.moveDeviceOverride(from: "old", to: "new")

        XCTAssertEqual(store.deviceOverrides["new"]?.name, "新")
        XCTAssertNil(store.deviceOverrides["old"])
    }

    func testCorruptedOverridesFallBackToEmpty() {
        defaults.set(Data([0xff]), forKey: "settings.deviceOverrides")
        XCTAssertTrue(SettingsStore(defaults: defaults).deviceOverrides.isEmpty)
    }

    func testAuxiliaryDeviceSavedByOlderVersionStillDecodes() throws {
        // 旧版本没有 airPodsModel 字段。
        let legacy = Data(#"[{"id":"x","name":"iPhone","advertisement":"type=0x10"}]"#.utf8)
        defaults.set(legacy, forKey: "settings.auxiliaryDevices")

        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.auxiliaryDevices.map(\.name), ["iPhone"])
        XCTAssertNil(store.auxiliaryDevices.first?.airPodsModel)
    }
}
