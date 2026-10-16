import Foundation
import XCTest

@testable import WatchLock

/// Apple Continuity 广播解析：只验证结构解析，不假设任何类型字节的语义。
final class AppleAdvertisementTests: XCTestCase {
    private func appleData(type: UInt8, length: UInt8, body: [UInt8] = []) -> Data {
        Data([0x4C, 0x00, type, length] + body)
    }

    func testParsesAppleManufacturerData() {
        let payload = AppleAdvertisement.parse(appleData(type: 0x10, length: 11, body: [0x01, 0x19]))
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.type, 0x10)
        XCTAssertEqual(payload?.declaredLength, 11)
        XCTAssertEqual(payload?.body, [0x01, 0x19])
        XCTAssertEqual(payload?.typeHex, "0x10")
    }

    func testDetectsTruncatedPayload() {
        // CoreBluetooth 常把厂商数据截断，声明长度与实际长度要分开保存。
        let payload = AppleAdvertisement.parse(appleData(type: 0x0F, length: 20, body: [0xAA]))
        XCTAssertFalse(payload?.isComplete ?? true)
        XCTAssertEqual(payload?.body.count, 1)
    }

    func testFingerprintIgnoresRollingPayloadAndLength() {
        // payload 会随时间变化；声明长度也会随设备状态变化，因此指纹只能取类型字节。
        let first = AppleAdvertisement.parse(appleData(type: 0x10, length: 11, body: [0x01, 0x02]))
        let second = AppleAdvertisement.parse(appleData(type: 0x10, length: 5, body: [0x99, 0x88]))
        XCTAssertEqual(first?.fingerprint, second?.fingerprint)
        XCTAssertEqual(first?.fingerprint, "type=0x10")
    }

    /// 本机真机抓包样本（2026-10-15）：Apple Watch 与 iPhone 的 Continuity 类型同为 0x10，
    /// 只有长度不同（手表 5、iPhone 7），说明类型字节不能单独区分手表，只能作辅助证据。
    func testRealCaptureFromAppleWatch() {
        let watch = Data([0x4C, 0x00, 0x10, 0x05, 0x27, 0x98, 0xD3, 0x30, 0x85])
        let payload = AppleAdvertisement.parse(watch)
        XCTAssertEqual(payload?.type, 0x10)
        XCTAssertEqual(payload?.declaredLength, 5)
        XCTAssertTrue(payload?.isComplete ?? false)
        XCTAssertEqual(payload?.fingerprint, "type=0x10")

        // 名称里是「@」而不是空格，归一化后必须仍能识别为手表。
        let result = WatchMatcher.evaluate(
            name: "Zero@Apple Watch",
            serviceUUIDs: [],
            manufacturerData: watch,
            boundIdentifier: nil,
            peripheralIdentifier: UUID()
        )
        XCTAssertTrue(result.isStrongCandidate)
        XCTAssertTrue(result.reasons.contains("名称匹配 Apple Watch"))
    }

    func testRejectsNonAppleOrTooShortData() {
        XCTAssertNil(AppleAdvertisement.parse(Data([0x4C, 0x00])))
        XCTAssertNil(AppleAdvertisement.parse(Data([0x11, 0x22, 0x10, 0x08])))
        XCTAssertNil(AppleAdvertisement.parse(nil))
        XCTAssertFalse(AppleAdvertisement.isApple(Data([0x11, 0x22, 0x33])))
        XCTAssertTrue(AppleAdvertisement.isApple(Data([0x4C, 0x00, 0x10])))
    }

    func testHexIsLimitedForLogging() {
        let data = Data([0x4C, 0x00, 0x10, 0x20] + Array(repeating: UInt8(0xAB), count: 20))
        let text = AppleAdvertisement.hex(data, limit: 4)
        XCTAssertTrue(text?.hasPrefix("4c 00 10 20") ?? false)
        XCTAssertTrue(text?.contains("共 24 字节") ?? false)
        XCTAssertNil(AppleAdvertisement.hex(nil))
    }

    func testDescribeFallsBackForUnparsableAppleData() {
        let unparsable = Data([0x4C, 0x00])
        XCTAssertNotNil(AppleAdvertisement.describe(unparsable))
        XCTAssertNil(AppleAdvertisement.describe(Data([0x11, 0x22, 0x33, 0x44])))
    }

    // MARK: - 地址轮换时按广播指纹校验

    func testRebindAcceptsSameAdvertisementType() {
        let manu = appleData(type: 0x10, length: 11, body: [0x01])
        XCTAssertTrue(WatchMatcher.shouldRebind(
            boundIdentifier: UUID().uuidString,
            boundName: "Apple Watch",
            candidateIdentifier: UUID(),
            candidateName: "Apple Watch",
            boundAdvertisement: AppleAdvertisement.parse(manu)?.fingerprint,
            candidateManufacturerData: manu
        ))
    }

    func testRebindRejectsDifferentAdvertisementType() {
        // 同名但广播类型不同：不是同一类设备，不能顶替已绑定手表。
        XCTAssertFalse(WatchMatcher.shouldRebind(
            boundIdentifier: UUID().uuidString,
            boundName: "Apple Watch",
            candidateIdentifier: UUID(),
            candidateName: "Apple Watch",
            boundAdvertisement: "type=0x10",
            candidateManufacturerData: appleData(type: 0x05, length: 11, body: [0x01])
        ))
    }

    func testRebindFallsBackToNameWhenCannotParse() {
        // 解析不出指纹时不能拒绝续接，否则会因为「收不到样本」而误锁。
        XCTAssertTrue(WatchMatcher.shouldRebind(
            boundIdentifier: UUID().uuidString,
            boundName: "Apple Watch",
            candidateIdentifier: UUID(),
            candidateName: "Apple Watch",
            boundAdvertisement: "type=0x10",
            candidateManufacturerData: nil
        ))
    }
}
