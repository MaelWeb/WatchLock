import Foundation
import XCTest

@testable import WatchLock

/// Proximity Pairing 广播里的 AirPods 型号解析：表内才认，表外 / 结构不对一律 nil。
final class AirPodsModelTests: XCTestCase {
    private func pairing(type: UInt8 = 0x07, prefix: UInt8 = 0x01, model: [UInt8], tail: [UInt8] = [0x55, 0x99]) -> Data {
        Data([0x4C, 0x00, type, 0x19, prefix] + model + tail)
    }

    func testParsesKnownModelIDs() {
        XCTAssertEqual(AppleAdvertisement.airPodsModel(from: pairing(model: [0x0E, 0x20])), .airPodsPro)
        XCTAssertEqual(AppleAdvertisement.airPodsModel(from: pairing(model: [0x14, 0x20])), .airPodsPro2)
        XCTAssertEqual(AppleAdvertisement.airPodsModel(from: pairing(model: [0x0A, 0x20])), .airPodsMax)
        XCTAssertEqual(AppleAdvertisement.airPodsModel(from: pairing(model: [0x13, 0x20])), .airPods3)
    }

    func testModelMapsToIconKind() {
        XCTAssertEqual(AirPodsModel.airPodsPro2USBC.kind, .airPodsPro)
        XCTAssertEqual(AirPodsModel.airPodsMax.kind, .airPodsMax)
        XCTAssertEqual(AirPodsModel.airPods2.kind, .airPods)
    }

    func testTruncatedPayloadStillIdentifiedFromFirstThreeBytes() {
        // CoreBluetooth 可能截断后面的内容，只要前 3 个字节在就够了。
        let data = Data([0x4C, 0x00, 0x07, 0x19, 0x01, 0x0E, 0x20])
        XCTAssertEqual(AppleAdvertisement.airPodsModel(from: data), .airPodsPro)
    }

    func testUnknownModelIDIsNotGuessed() {
        XCTAssertNil(AppleAdvertisement.airPodsModel(from: pairing(model: [0xFF, 0xFF])))
    }

    func testOtherContinuityTypesAreIgnored() {
        // 手表 / iPhone 的 0x10 广播即使字节碰巧像型号 ID 也不能被认成 AirPods。
        XCTAssertNil(AppleAdvertisement.airPodsModel(from: pairing(type: 0x10, model: [0x0E, 0x20])))
    }

    func testWrongPrefixOrTooShortIsRejected() {
        XCTAssertNil(AppleAdvertisement.airPodsModel(from: pairing(prefix: 0x02, model: [0x0E, 0x20])))
        XCTAssertNil(AppleAdvertisement.airPodsModel(from: Data([0x4C, 0x00, 0x07, 0x19, 0x01, 0x0E])))
    }

    func testNonAppleOrMissingDataIsRejected() {
        XCTAssertNil(AppleAdvertisement.airPodsModel(from: nil))
        XCTAssertNil(AppleAdvertisement.airPodsModel(from: Data([0x11, 0x22, 0x07, 0x19, 0x01, 0x0E, 0x20])))
    }
}
