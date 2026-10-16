import CoreBluetooth
import XCTest
@testable import WatchLock

/// Apple Watch 候选识别（FR-02 多证据规则）。
final class WatchMatcherTests: XCTestCase {
    private let identifier = UUID()

    private func evaluate(
        name: String? = nil,
        serviceUUIDs: [CBUUID] = [],
        manufacturerData: Data? = nil,
        boundIdentifier: UUID? = nil
    ) -> WatchMatcher.Result {
        WatchMatcher.evaluate(
            name: name,
            serviceUUIDs: serviceUUIDs,
            manufacturerData: manufacturerData,
            boundIdentifier: boundIdentifier,
            peripheralIdentifier: identifier
        )
    }

    func testBoundDeviceIsAlwaysCandidate() {
        let result = evaluate(name: "Random", boundIdentifier: identifier)
        XCTAssertTrue(result.isCandidate)
        XCTAssertTrue(result.reasons.contains("已绑定设备"))
    }

    func testNameMatch() {
        let appleWatch = evaluate(name: "Apple Watch Ultra")
        XCTAssertTrue(appleWatch.isCandidate)
        XCTAssertTrue(appleWatch.reasons.contains("名称匹配 Apple Watch"))

        let generic = evaluate(name: "My iWatch")
        XCTAssertTrue(generic.reasons.contains("名称包含 watch"))
    }

    func testAppleServiceUUIDMatch() {
        let uuid = WatchMatcher.appleRelatedServiceUUIDs.first!
        let result = evaluate(name: "Unknown", serviceUUIDs: [uuid])
        XCTAssertTrue(result.isCandidate)
        XCTAssertTrue(result.reasons.contains("命中 Apple 服务 UUID"))
    }

    func testAppleManufacturerData() {
        let result = evaluate(name: "Unknown", manufacturerData: Data([0x4C, 0x00, 0x01]))
        XCTAssertTrue(result.isCandidate)
        XCTAssertTrue(result.reasons.contains("厂商数据为 Apple"))
        // 办公室环境常有上百台 Apple 设备广播，仅厂商数据只是弱候选。
        XCTAssertFalse(result.isStrongCandidate)
    }

    func testAppleWatchNameIsStrongCandidate() {
        let result = evaluate(name: "Zero@Apple Watch", manufacturerData: Data([0x4C, 0x00, 0x10, 0x05]))
        XCTAssertTrue(result.isStrongCandidate)
    }

    /// 广播名里的空格常是 U+00A0（不间断空格），必须归一化后仍能被识别。
    func testNameWithNonBreakingSpaceIsStrongCandidate() {
        let result = evaluate(name: "Zero@Apple\u{00A0}Watch")
        XCTAssertTrue(result.isCandidate)
        XCTAssertTrue(result.isStrongCandidate)
        XCTAssertTrue(result.reasons.contains("名称匹配 Apple Watch"))
    }

    func testDeviceTypeOnlyNameIsWeakCandidate() {
        let result = evaluate(name: "HUAWEI WATCH FIT 4-B99")
        XCTAssertTrue(result.isCandidate)
        XCTAssertFalse(result.isStrongCandidate)
    }

    func testNonAppleManufacturerDataIsRejected() {
        let result = evaluate(name: "Speaker", manufacturerData: Data([0x57, 0x00]))
        XCTAssertFalse(result.isCandidate)
    }

    func testNoEvidenceIsNotCandidate() {
        let result = evaluate(name: "Some Earbuds")
        XCTAssertFalse(result.isCandidate)
        XCTAssertTrue(result.reasons.isEmpty)
    }

    /// 蓝牙地址轮换（RPA）后，同名设备应被认成同一只手表。
    func testRebindOnAddressRotation() {
        let boundID = UUID()
        let rotatedID = UUID()

        XCTAssertTrue(WatchMatcher.shouldRebind(
            boundIdentifier: boundID.uuidString,
            boundName: "Apple Watch",
            candidateIdentifier: rotatedID,
            candidateName: "Apple Watch"
        ))
        XCTAssertFalse(WatchMatcher.shouldRebind(
            boundIdentifier: boundID.uuidString,
            boundName: "Apple Watch",
            candidateIdentifier: boundID,
            candidateName: "Apple Watch"
        ), "地址没变时不需要重新绑定")
        XCTAssertFalse(WatchMatcher.shouldRebind(
            boundIdentifier: boundID.uuidString,
            boundName: "Apple Watch",
            candidateIdentifier: rotatedID,
            candidateName: "Other Watch"
        ))
        XCTAssertFalse(WatchMatcher.shouldRebind(
            boundIdentifier: boundID.uuidString,
            boundName: "Apple Watch",
            candidateIdentifier: rotatedID,
            candidateName: ""
        ))
        XCTAssertFalse(WatchMatcher.shouldRebind(
            boundIdentifier: nil,
            boundName: "Apple Watch",
            candidateIdentifier: rotatedID,
            candidateName: "Apple Watch"
        ), "未绑定时不需要迁移")
    }

    func testShortManufacturerDataIsIgnored() {
        let result = evaluate(name: nil, manufacturerData: Data([0x4C]))
        XCTAssertFalse(result.isCandidate)
    }
}
