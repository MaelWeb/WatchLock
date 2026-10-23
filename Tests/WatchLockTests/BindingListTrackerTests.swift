import Foundation
import XCTest

@testable import WatchLock

/// 绑定候选列表的稳定性：出现过的设备不能瞬间消失，行也不能随信号抖动来回跳。
final class BindingListTrackerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 2_000_000)

    private func device(_ index: Int, rssi: Int, seen: Date, reasons: Set<String> = []) -> DiscoveredWatch {
        DiscoveredWatch(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!,
            name: "",
            rssi: rssi,
            lastSeen: seen,
            matchReasons: reasons
        )
    }

    private func ids(_ devices: [DiscoveredWatch]) -> [Int] {
        devices.map { Int($0.id.uuidString.suffix(12))! }
    }

    func testDeviceStaysAfterDroppingOutOfTopRanks() {
        var tracker = BindingListTracker(config: .init(limit: 2))
        let a = device(1, rssi: -40, seen: t0)
        let b = device(2, rssi: -50, seen: t0)
        tracker.update(strong: [], all: [a, b], now: t0)
        XCTAssertEqual(Set(ids(tracker.visible)), [1, 2])

        // 两台更强的设备出现，b 掉出前 2 名，但仍在广播，必须留在列表里。
        let now = t0.addingTimeInterval(1)
        let c = device(3, rssi: -30, seen: now)
        let d = device(4, rssi: -35, seen: now)
        tracker.update(strong: [], all: [a.seen(now), b.seen(now), c, d], now: now)

        XCTAssertTrue(ids(tracker.visible).contains(2), "还在广播的设备不能被新来的挤掉")
        XCTAssertEqual(tracker.visible.count, 4)
    }

    func testDeviceRemovedAfterHoldWithoutAdvertisements() {
        var tracker = BindingListTracker(config: .init(hold: 90))
        let a = device(1, rssi: -40, seen: t0)
        tracker.update(strong: [], all: [a], now: t0)

        // 89 秒没广播：仍在。
        tracker.update(strong: [], all: [a], now: t0.addingTimeInterval(89))
        XCTAssertEqual(ids(tracker.visible), [1])

        // 超过 90 秒：移除。
        tracker.update(strong: [], all: [a], now: t0.addingTimeInterval(91))
        XCTAssertTrue(tracker.visible.isEmpty)
    }

    func testDeviceRemovedWhenScannerForgetsIt() {
        var tracker = BindingListTracker()
        let a = device(1, rssi: -40, seen: t0)
        tracker.update(strong: [], all: [a], now: t0)
        tracker.update(strong: [], all: [], now: t0.addingTimeInterval(1))
        XCTAssertTrue(tracker.visible.isEmpty)
    }

    func testLongSilentDeviceIsNotAdmittedBySignalAlone() {
        var tracker = BindingListTracker(config: .init(hold: 90))
        let stale = device(1, rssi: -30, seen: t0)
        tracker.update(strong: [], all: [stale], now: t0.addingTimeInterval(600))
        XCTAssertTrue(tracker.visible.isEmpty)
    }

    func testStrongCandidateIsNotExpiredByHold() {
        var tracker = BindingListTracker(config: .init(hold: 90))
        let watch = device(1, rssi: -60, seen: t0, reasons: ["名称匹配 Apple Watch"])
        tracker.update(strong: [watch], all: [watch], now: t0)
        tracker.update(strong: [watch], all: [watch], now: t0.addingTimeInterval(300))
        XCTAssertEqual(ids(tracker.visible), [1])
    }

    func testOrderDoesNotJumpOnSmallSignalJitter() {
        var tracker = BindingListTracker()
        var a = device(1, rssi: -50, seen: t0)
        var b = device(2, rssi: -52, seen: t0)
        tracker.update(strong: [], all: [a, b], now: t0)
        let initial = ids(tracker.visible)

        // b 瞬时比 a 强 3 dB：同一档位内不重排。
        for step in 1...5 {
            let now = t0.addingTimeInterval(Double(step))
            a = device(1, rssi: -53, seen: now)
            b = device(2, rssi: -50, seen: now)
            tracker.update(strong: [], all: [a, b], now: now)
            XCTAssertEqual(ids(tracker.visible), initial)
        }
    }

    func testSustainedSignalChangeReorders() {
        var tracker = BindingListTracker()
        tracker.update(strong: [], all: [device(1, rssi: -70, seen: t0), device(2, rssi: -50, seen: t0)], now: t0)
        XCTAssertEqual(ids(tracker.visible), [2, 1])

        // 1 号持续变得非常强：平滑值跨过分档后应排到前面。
        for step in 1...20 {
            let now = t0.addingTimeInterval(Double(step))
            tracker.update(strong: [], all: [device(1, rssi: -30, seen: now), device(2, rssi: -50, seen: now)], now: now)
        }
        XCTAssertEqual(ids(tracker.visible), [1, 2])
    }

    func testNewStrongerDeviceIsAdmittedEvenWhenListIsFull() {
        var tracker = BindingListTracker(config: .init(limit: 2))
        tracker.update(strong: [], all: [device(1, rssi: -60, seen: t0), device(2, rssi: -65, seen: t0)], now: t0)

        // 手表贴近 Mac：新来的最强设备必须马上能选，不能被已钉住的旧设备挡在外面。
        let now = t0.addingTimeInterval(1)
        let near = device(3, rssi: -35, seen: now)
        tracker.update(
            strong: [],
            all: [device(1, rssi: -60, seen: now), device(2, rssi: -65, seen: now), near],
            now: now
        )
        XCTAssertEqual(ids(tracker.visible).first, 3)
    }

    func testMaxVisibleEvictsWeakestNonStrong() {
        var tracker = BindingListTracker(config: .init(limit: 100, maxVisible: 3))
        let devices = (1...5).map { device($0, rssi: -40 - $0 * 10, seen: t0) }
        tracker.update(strong: [], all: devices, now: t0)
        XCTAssertEqual(Set(ids(tracker.visible)), [1, 2, 3])
    }

    func testStrongCandidatesAreNeverEvictedByCapacity() {
        var tracker = BindingListTracker(config: .init(limit: 100, maxVisible: 1))
        let weakWatch = device(1, rssi: -90, seen: t0, reasons: ["名称匹配 Apple Watch"])
        let loud = device(2, rssi: -30, seen: t0)
        tracker.update(strong: [weakWatch], all: [weakWatch, loud], now: t0)
        XCTAssertEqual(ids(tracker.visible), [1])
    }

    func testUnknownSignalSortsLastAndOrderIsDeterministic() {
        let unknown = device(1, rssi: 127, seen: t0)
        let known = device(2, rssi: -80, seen: t0)
        XCTAssertEqual(ids(DiscoveredWatch.mergedBindingList(strong: [], all: [unknown, known], limit: 8)), [2, 1])

        // 信号相同时按标识排序，多次结果一致。
        let first = (3...8).map { device($0, rssi: 127, seen: t0) }
        let results = (0..<5).map { _ in ids(DiscoveredWatch.mergedBindingList(strong: [], all: first.shuffled(), limit: 8)) }
        XCTAssertEqual(Set(results).count, 1)
    }

    func testUnknownSignalDoesNotPoisonSmoothing() {
        var tracker = BindingListTracker()
        tracker.update(strong: [], all: [device(1, rssi: -50, seen: t0)], now: t0)
        tracker.update(strong: [], all: [device(1, rssi: 127, seen: t0.addingTimeInterval(1))], now: t0.addingTimeInterval(1))
        tracker.update(strong: [], all: [device(2, rssi: -60, seen: t0.addingTimeInterval(1)), device(1, rssi: 127, seen: t0.addingTimeInterval(1))], now: t0.addingTimeInterval(1))
        // 1 号保留之前的平滑值（-50），仍排在 2 号（-60）之前。
        XCTAssertEqual(ids(tracker.visible), [1, 2])
    }
}

private extension DiscoveredWatch {
    func seen(_ date: Date) -> DiscoveredWatch {
        var copy = self
        copy.lastSeen = date
        return copy
    }
}

/// 辅助设备列表：有名称的设备优先入选，不被周围大量无名 Apple 广播挤掉。
final class BindingListTrackerAdmissionOrderTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 3_000_000)

    private func device(_ index: Int, name: String, rssi: Int) -> DiscoveredWatch {
        DiscoveredWatch(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!,
            name: name,
            rssi: rssi,
            lastSeen: t0,
            matchReasons: []
        )
    }

    func testNamedDevicesAreAdmittedBeforeLouderUnnamedOnes() {
        var tracker = BindingListTracker(config: .init(limit: 2, admissionOrder: { lhs, rhs in
            if lhs.name.isEmpty != rhs.name.isEmpty { return !lhs.name.isEmpty }
            return DiscoveredWatch.isRankedBefore(lhs, rhs)
        }))
        let loudUnnamed = (1...5).map { device($0, name: "", rssi: -40) }
        let quietNamed = device(9, name: "Zero's iPhone", rssi: -85)

        tracker.update(strong: [], all: loudUnnamed + [quietNamed], now: t0)

        XCTAssertTrue(tracker.visible.contains { $0.name == "Zero's iPhone" })
        XCTAssertEqual(tracker.visible.count, 2)
    }
}
