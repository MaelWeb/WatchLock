import Foundation
import XCTest

@testable import WatchLock

/// 名称 / 型号缓存：间歇性出现的信息要能沿用，但不能永久沿用，也不能无限增长。
final class DeviceIdentityCacheTests: XCTestCase {
    private let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testNamelessFrameReusesEarlierName() {
        var cache = DeviceIdentityCache()
        cache.record(id: id, name: "Zero's iPhone", model: nil, now: t0)
        cache.record(id: id, name: nil, model: nil, now: t0.addingTimeInterval(5))

        XCTAssertEqual(cache.name(for: id, now: t0.addingTimeInterval(6)), "Zero's iPhone")
    }

    func testEmptyNameDoesNotOverwriteRealName() {
        var cache = DeviceIdentityCache()
        cache.record(id: id, name: "Apple Watch", model: nil, now: t0)
        cache.record(id: id, name: "", model: nil, now: t0.addingTimeInterval(1))

        XCTAssertEqual(cache.name(for: id, now: t0.addingTimeInterval(2)), "Apple Watch")
    }

    func testNewNameReplacesOldName() {
        var cache = DeviceIdentityCache()
        cache.record(id: id, name: "Old", model: nil, now: t0)
        cache.record(id: id, name: "New", model: nil, now: t0.addingTimeInterval(1))

        XCTAssertEqual(cache.name(for: id, now: t0.addingTimeInterval(2)), "New")
    }

    func testModelIsCachedIndependentlyOfName() {
        var cache = DeviceIdentityCache()
        cache.record(id: id, name: nil, model: .airPodsPro, now: t0)
        cache.record(id: id, name: nil, model: nil, now: t0.addingTimeInterval(30))

        XCTAssertEqual(cache.model(for: id, now: t0.addingTimeInterval(31)), .airPodsPro)
    }

    func testEntryExpiresAfterTimeToLive() {
        var cache = DeviceIdentityCache(timeToLive: 60)
        cache.record(id: id, name: "Watch", model: nil, now: t0)

        XCTAssertEqual(cache.name(for: id, now: t0.addingTimeInterval(60)), "Watch")
        XCTAssertNil(cache.name(for: id, now: t0.addingTimeInterval(61)))
    }

    func testContinuousSightingsKeepEntryAlive() {
        var cache = DeviceIdentityCache(timeToLive: 60)
        cache.record(id: id, name: "Watch", model: nil, now: t0)
        cache.record(id: id, name: nil, model: nil, now: t0.addingTimeInterval(50))

        XCTAssertEqual(cache.name(for: id, now: t0.addingTimeInterval(100)), "Watch")
    }

    func testExpiredValueIsNotRevivedBySightingWithoutName() {
        var cache = DeviceIdentityCache(timeToLive: 60)
        cache.record(id: id, name: "Watch", model: nil, now: t0)
        cache.record(id: id, name: nil, model: nil, now: t0.addingTimeInterval(120))

        XCTAssertNil(cache.name(for: id, now: t0.addingTimeInterval(121)))
    }

    func testPruneDropsExpiredEntries() {
        var cache = DeviceIdentityCache(timeToLive: 60)
        cache.record(id: id, name: "Watch", model: nil, now: t0)
        cache.prune(now: t0.addingTimeInterval(61))

        XCTAssertEqual(cache.count, 0)
    }

    func testCapacityEvictsLeastRecentlySeen() {
        var cache = DeviceIdentityCache(capacity: 2)
        let a = UUID(), b = UUID(), c = UUID()
        cache.record(id: a, name: "A", model: nil, now: t0)
        cache.record(id: b, name: "B", model: nil, now: t0.addingTimeInterval(1))
        cache.record(id: c, name: "C", model: nil, now: t0.addingTimeInterval(2))

        XCTAssertEqual(cache.count, 2)
        XCTAssertNil(cache.name(for: a, now: t0.addingTimeInterval(3)))
        XCTAssertEqual(cache.name(for: c, now: t0.addingTimeInterval(3)), "C")
    }

    func testFrameWithoutIdentityInfoCreatesNoEntry() {
        var cache = DeviceIdentityCache()
        cache.record(id: id, name: nil, model: nil, now: t0)
        XCTAssertEqual(cache.count, 0)
    }
}
