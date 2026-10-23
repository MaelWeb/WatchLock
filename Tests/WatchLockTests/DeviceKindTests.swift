import XCTest
@testable import WatchLock

/// 设备列表按名称区分图标；无法识别时回退通用图标，而不是误标成手表。
final class DeviceKindTests: XCTestCase {
    func testInfersKindFromName() {
        XCTAssertEqual(DeviceKind.infer(fromName: "Zero@Apple Watch"), .watch)
        XCTAssertEqual(DeviceKind.infer(fromName: "Zero's iPhone"), .iPhone)
        XCTAssertEqual(DeviceKind.infer(fromName: "iPad Air"), .iPad)
        XCTAssertEqual(DeviceKind.infer(fromName: "MacBook Pro"), .laptop)
        XCTAssertEqual(DeviceKind.infer(fromName: "Mac mini"), .desktop)
        XCTAssertEqual(DeviceKind.infer(fromName: "HomePod"), .homePod)
    }

    func testSpecificAirPodsModelsWinOverGenericRule() {
        XCTAssertEqual(DeviceKind.infer(fromName: "Zero's AirPods Pro"), .airPodsPro)
        XCTAssertEqual(DeviceKind.infer(fromName: "AirPods Max"), .airPodsMax)
        XCTAssertEqual(DeviceKind.infer(fromName: "AirPods"), .airPods)
    }

    func testNonBreakingSpaceInNameIsNormalized() {
        // Apple Watch 广播名里的空格常是 U+00A0
        XCTAssertEqual(DeviceKind.infer(fromName: "Apple\u{00A0}Watch"), .watch)
    }

    func testEmptyOrUnknownNameFallsBackToGenericIcon() {
        XCTAssertEqual(DeviceKind.infer(fromName: ""), .unknown)
        XCTAssertEqual(DeviceKind.infer(fromName: "XYZ-123"), .unknown)
        XCTAssertEqual(DeviceKind.unknown.symbolName, "dot.radiowaves.left.and.right")
    }
}
