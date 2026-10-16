import XCTest
@testable import WatchLock

/// 绑定列表不依赖名称匹配：无名但离得最近的设备也应可选。
final class BindingCandidatesTests: XCTestCase {
    private func device(id: String, name: String = "", rssi: Int, reasons: Set<String> = []) -> DiscoveredWatch {
        DiscoveredWatch(
            id: UUID(uuidString: id)!,
            name: name,
            rssi: rssi,
            lastSeen: Date(),
            matchReasons: reasons
        )
    }

    func testNamelessButClosestDeviceIsOffered() {
        let nameless = device(id: "00000000-0000-0000-0000-000000000001", rssi: -35)
        let far = device(id: "00000000-0000-0000-0000-000000000002", rssi: -80)

        let result = DiscoveredWatch.mergedBindingList(strong: [], all: [far, nameless], limit: 8)

        XCTAssertEqual(result.first?.id, nameless.id)
        XCTAssertTrue(result.first?.matchReasons.contains("靠近 Mac（按信号排序）") ?? false)
    }

    func testStrongCandidateIsKeptEvenWhenWeaker() {
        let watch = device(
            id: "00000000-0000-0000-0000-000000000001",
            name: "Zero@Apple Watch",
            rssi: -70,
            reasons: ["名称匹配 Apple Watch"]
        )
        let loud = device(id: "00000000-0000-0000-0000-000000000002", rssi: -40)

        let result = DiscoveredWatch.mergedBindingList(strong: [watch], all: [loud], limit: 8)

        XCTAssertEqual(result.count, 2)
        let kept = result.first { $0.id == watch.id }
        // 强候选保留自身识别依据，不被「按信号排序」覆盖
        XCTAssertEqual(kept?.matchReasons, ["名称匹配 Apple Watch"])
    }

    func testNoDuplicateAndSortedByRSSI() {
        let a = device(id: "00000000-0000-0000-0000-000000000001", rssi: -40)
        let b = device(id: "00000000-0000-0000-0000-000000000002", rssi: -50)

        let result = DiscoveredWatch.mergedBindingList(strong: [b], all: [a, b], limit: 8)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.rssi), [-40, -50])
    }

    func testLimitIsAppliedToSignalRankedTail() {
        let devices = (1...20).map {
            device(id: String(format: "00000000-0000-0000-0000-%012d", $0), rssi: -30 - $0)
        }
        let result = DiscoveredWatch.mergedBindingList(strong: [], all: devices, limit: 5)
        XCTAssertEqual(result.count, 5)
        XCTAssertEqual(result.first?.rssi, -31)
    }
}
