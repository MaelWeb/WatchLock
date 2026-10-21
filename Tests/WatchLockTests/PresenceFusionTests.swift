import XCTest
@testable import WatchLock

final class PresenceFusionEvidenceTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 5_000)
    private var config: PresenceFusion.Config { .init(enabled: true, nearRSSI: -80, freshness: 20, maxHold: 120) }

    func testStrongFreshReadingCountsAsNear() {
        var evidence = PresenceFusion.Evidence()
        evidence.record(id: "phone", rssi: -60, at: t0, window: 20)
        XCTAssertEqual(evidence.nearIDs(now: t0.addingTimeInterval(5), config: config), ["phone"])
    }

    func testWeakReadingIsNotNear() {
        var evidence = PresenceFusion.Evidence()
        evidence.record(id: "phone", rssi: -92, at: t0, window: 20)
        XCTAssertTrue(evidence.nearIDs(now: t0, config: config).isEmpty)
    }

    func testStaleReadingExpires() {
        var evidence = PresenceFusion.Evidence()
        evidence.record(id: "phone", rssi: -50, at: t0, window: 20)
        XCTAssertTrue(evidence.nearIDs(now: t0.addingTimeInterval(21), config: config).isEmpty)
    }

    func testBestReadingInWindowWinsOverSingleDip() {
        var evidence = PresenceFusion.Evidence()
        evidence.record(id: "phone", rssi: -60, at: t0, window: 20)
        evidence.record(id: "phone", rssi: -95, at: t0.addingTimeInterval(3), window: 20)
        XCTAssertEqual(evidence.nearIDs(now: t0.addingTimeInterval(4), config: config), ["phone"])
    }

    func testOldReadingsAreTrimmedOnRecord() {
        var evidence = PresenceFusion.Evidence()
        evidence.record(id: "phone", rssi: -50, at: t0, window: 20)
        evidence.record(id: "phone", rssi: -95, at: t0.addingTimeInterval(30), window: 20)
        XCTAssertTrue(evidence.nearIDs(now: t0.addingTimeInterval(30), config: config).isEmpty)
    }

    func testKeepOnlyDropsRemovedDevices() {
        var evidence = PresenceFusion.Evidence()
        evidence.record(id: "a", rssi: -50, at: t0, window: 20)
        evidence.record(id: "b", rssi: -50, at: t0, window: 20)
        evidence.keepOnly(["b"])
        XCTAssertEqual(evidence.nearIDs(now: t0, config: config), ["b"])
    }

    func testMoveCarriesReadingsToNewIdentifier() {
        var evidence = PresenceFusion.Evidence()
        evidence.record(id: "old", rssi: -55, at: t0, window: 20)
        evidence.move(from: "old", to: "new")
        XCTAssertEqual(evidence.nearIDs(now: t0, config: config), ["new"])
    }

    func testResetClearsEverything() {
        var evidence = PresenceFusion.Evidence()
        evidence.record(id: "a", rssi: -50, at: t0, window: 20)
        evidence.reset()
        XCTAssertTrue(evidence.nearIDs(now: t0, config: config).isEmpty)
    }
}

final class PresenceFusionHoldTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 9_000)
    private var config: PresenceFusion.Config { .init(enabled: true, nearRSSI: -80, freshness: 20, maxHold: 120) }
    private func watch(
        far: Bool = true,
        lastSampleAt: Date? = nil,
        rssi: Double? = -52
    ) -> PresenceFusion.WatchView {
        .init(isFar: far, lastSampleAt: lastSampleAt ?? t0.addingTimeInterval(-60), smoothedRSSI: rssi, farRSSI: -70)
    }

    // MARK: request

    func testSignalLostWithNearAuxiliaryIsHeld() {
        var hold = PresenceFusion.Hold()
        XCTAssertTrue(hold.request(reason: .signalLost, nearIDs: ["phone"], now: t0, config: config))
        XCTAssertTrue(hold.isHolding)
        XCTAssertEqual(hold.holders, ["phone"])
    }

    func testBeyondThresholdIsNeverHeld() {
        // 手表明确很弱：把手机落在桌上走开是最常见的场景，辅助设备不能否决。
        var hold = PresenceFusion.Hold()
        XCTAssertFalse(hold.request(reason: .beyondThreshold, nearIDs: ["phone"], now: t0, config: config))
        XCTAssertFalse(hold.isHolding)
    }

    func testNoNearAuxiliaryMeansNoHold() {
        var hold = PresenceFusion.Hold()
        XCTAssertFalse(hold.request(reason: .signalLost, nearIDs: [], now: t0, config: config))
    }

    func testDisabledMeansNoHold() {
        var hold = PresenceFusion.Hold()
        var disabled = config
        disabled.enabled = false
        XCTAssertFalse(hold.request(reason: .signalLost, nearIDs: ["phone"], now: t0, config: disabled))
    }

    // MARK: tick

    func testIdleWhenNotHolding() {
        var hold = PresenceFusion.Hold()
        XCTAssertEqual(hold.tick(now: t0, config: config, nearIDs: ["phone"], watch: watch()), .idle)
    }

    func testKeepsHoldingWhileAuxiliaryStaysNear() {
        var hold = PresenceFusion.Hold()
        _ = hold.request(reason: .signalLost, nearIDs: ["phone"], now: t0, config: config)
        XCTAssertEqual(hold.tick(now: t0.addingTimeInterval(30), config: config, nearIDs: ["phone"], watch: watch()), .holding)
        XCTAssertEqual(hold.tick(now: t0.addingTimeInterval(119), config: config, nearIDs: ["phone"], watch: watch()), .holding)
    }

    func testReleasesAtHardCapEvenIfAuxiliaryStillNear() {
        var hold = PresenceFusion.Hold()
        _ = hold.request(reason: .signalLost, nearIDs: ["phone"], now: t0, config: config)
        XCTAssertEqual(hold.tick(now: t0.addingTimeInterval(120), config: config, nearIDs: ["phone"], watch: watch()),
                       .release(.capped, .signalLost))
        XCTAssertFalse(hold.isHolding)
    }

    func testReleasesWhenAuxiliaryDisappears() {
        var hold = PresenceFusion.Hold()
        _ = hold.request(reason: .signalLost, nearIDs: ["phone"], now: t0, config: config)
        XCTAssertEqual(hold.tick(now: t0.addingTimeInterval(10), config: config, nearIDs: [], watch: watch()),
                       .release(.auxiliaryGone, .signalLost))
    }

    func testCancelsWhenWatchComesBack() {
        var hold = PresenceFusion.Hold()
        _ = hold.request(reason: .signalLost, nearIDs: ["phone"], now: t0, config: config)
        XCTAssertEqual(hold.tick(now: t0.addingTimeInterval(10), config: config, nearIDs: ["phone"], watch: watch(far: false)),
                       .cancelled)
        XCTAssertFalse(hold.isHolding)
    }

    func testReleasesWhenWatchReappearsButWeak() {
        var hold = PresenceFusion.Hold()
        _ = hold.request(reason: .signalLost, nearIDs: ["phone"], now: t0, config: config)
        let reappeared = watch(lastSampleAt: t0.addingTimeInterval(8), rssi: -88)
        XCTAssertEqual(hold.tick(now: t0.addingTimeInterval(10), config: config, nearIDs: ["phone"], watch: reappeared),
                       .release(.watchConfirmedFar, .signalLost))
    }

    func testOldWatchSampleBeforeHoldDoesNotCountAsConfirmation() {
        // 暂缓开始之前的旧读数（即便很弱）不能当作「暂缓期间手表自己说它在远处」。
        var hold = PresenceFusion.Hold()
        _ = hold.request(reason: .signalLost, nearIDs: ["phone"], now: t0, config: config)
        let stale = watch(lastSampleAt: t0.addingTimeInterval(-30), rssi: -95)
        XCTAssertEqual(hold.tick(now: t0.addingTimeInterval(10), config: config, nearIDs: ["phone"], watch: stale), .holding)
    }

    func testReleasesWhenFeatureDisabledMidHold() {
        var hold = PresenceFusion.Hold()
        _ = hold.request(reason: .signalLost, nearIDs: ["phone"], now: t0, config: config)
        var disabled = config
        disabled.enabled = false
        XCTAssertEqual(hold.tick(now: t0.addingTimeInterval(5), config: disabled, nearIDs: ["phone"], watch: watch()),
                       .release(.disabled, .signalLost))
    }

    func testCancelClearsState() {
        var hold = PresenceFusion.Hold()
        _ = hold.request(reason: .signalLost, nearIDs: ["phone"], now: t0, config: config)
        hold.cancel()
        XCTAssertFalse(hold.isHolding)
        XCTAssertEqual(hold.tick(now: t0.addingTimeInterval(1), config: config, nearIDs: ["phone"], watch: watch()), .idle)
    }

    func testRepeatedRequestKeepsOriginalStartSoCapCannotBeExtended() {
        var hold = PresenceFusion.Hold()
        _ = hold.request(reason: .signalLost, nearIDs: ["phone"], now: t0, config: config)
        _ = hold.request(reason: .signalLost, nearIDs: ["phone"], now: t0.addingTimeInterval(100), config: config)
        XCTAssertEqual(hold.tick(now: t0.addingTimeInterval(120), config: config, nearIDs: ["phone"], watch: watch()),
                       .release(.capped, .signalLost))
    }
}

final class PresenceFusionRebindTests: XCTestCase {
    private func discovered(id: UUID = UUID(), name: String, rssi: Int = -60, manufacturer: Data? = nil) -> DiscoveredWatch {
        var device = DiscoveredWatch(id: id, name: name, rssi: rssi, lastSeen: Date(), matchReasons: [])
        device.manufacturerData = manufacturer
        return device
    }

    func testRebindsByNameWhenAddressRotates() {
        let old = AuxiliaryDevice(id: UUID().uuidString, name: "Eden 的 iPhone", advertisement: nil)
        let rotated = discovered(name: "Eden 的 iPhone")
        let result = PresenceFusion.rebindTarget(for: old, among: [rotated, discovered(name: "别人的 iPhone")], taken: [])
        XCTAssertEqual(result?.id, rotated.id)
    }

    func testUnnamedDeviceCannotRebind() {
        let old = AuxiliaryDevice(id: UUID().uuidString, name: "", advertisement: nil)
        XCTAssertNil(PresenceFusion.rebindTarget(for: old, among: [discovered(name: "")], taken: []))
    }

    func testDoesNotRebindToTakenIdentifier() {
        let old = AuxiliaryDevice(id: UUID().uuidString, name: "AirPods", advertisement: nil)
        let other = discovered(name: "AirPods")
        XCTAssertNil(PresenceFusion.rebindTarget(for: old, among: [other], taken: [other.id.uuidString]))
    }

    func testPicksStrongestWhenSeveralMatch() {
        let old = AuxiliaryDevice(id: UUID().uuidString, name: "AirPods", advertisement: nil)
        let weak = discovered(name: "AirPods", rssi: -88)
        let strong = discovered(name: "AirPods", rssi: -52)
        XCTAssertEqual(PresenceFusion.rebindTarget(for: old, among: [weak, strong], taken: [])?.id, strong.id)
    }

    func testSameIdentifierIsNotARebind() {
        let id = UUID()
        let old = AuxiliaryDevice(id: id.uuidString, name: "AirPods", advertisement: nil)
        XCTAssertNil(PresenceFusion.rebindTarget(for: old, among: [discovered(id: id, name: "AirPods")], taken: []))
    }

    func testAuxiliaryDeviceCodableRoundTrip() throws {
        let devices = [AuxiliaryDevice(id: "x", name: "iPhone", advertisement: "type=0x10"),
                       AuxiliaryDevice(id: "y", name: "", advertisement: nil)]
        let decoded = try JSONDecoder().decode([AuxiliaryDevice].self, from: JSONEncoder().encode(devices))
        XCTAssertEqual(decoded, devices)
    }
}
