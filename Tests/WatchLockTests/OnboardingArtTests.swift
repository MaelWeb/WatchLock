import XCTest
@testable import WatchLock

/// 引导插画的阶段选择：保证插画与状态卡 / 步骤口径一致，不会在蓝牙已就绪时还画「连不上」。
final class OnboardingArtTests: XCTestCase {
    func testPermissionStepWithoutBluetoothShowsBrokenLink() {
        XCTAssertEqual(OnboardingArtStage.stage(forStep: 0, bluetoothReady: false), .needsPermission)
    }

    func testPermissionStepWithBluetoothReadyAlreadyShowsSearching() {
        // 状态卡此时写「蓝牙已就绪，扫描已开始」，插画不能再画断开的虚线。
        XCTAssertEqual(OnboardingArtStage.stage(forStep: 0, bluetoothReady: true), .searching)
    }

    func testDeviceStepAlwaysSearching() {
        XCTAssertEqual(OnboardingArtStage.stage(forStep: 1, bluetoothReady: true), .searching)
        XCTAssertEqual(OnboardingArtStage.stage(forStep: 1, bluetoothReady: false), .searching)
    }

    func testReadyStepShowsCheck() {
        XCTAssertEqual(OnboardingArtStage.stage(forStep: 2, bluetoothReady: true), .ready)
        XCTAssertEqual(OnboardingArtStage.stage(forStep: 2, bluetoothReady: false), .ready)
    }

    func testOutOfRangeStepsClampToNearestStage() {
        XCTAssertEqual(OnboardingArtStage.stage(forStep: -1, bluetoothReady: false), .needsPermission)
        XCTAssertEqual(OnboardingArtStage.stage(forStep: 9, bluetoothReady: false), .ready)
    }
}

/// 设置页数值项的显示文案：单位与取整规则集中在 `ValueFormat`。
final class ValueFormatTests: XCTestCase {
    func testDBmKeepsSignAndUnit() {
        XCTAssertEqual(ValueFormat.dBm(-55), "-55 dBm")
    }

    func testSecondsDropsFraction() {
        XCTAssertEqual(ValueFormat.seconds(5), "5 秒")
        XCTAssertEqual(ValueFormat.seconds(20.9), "20 秒")
    }

    func testMinutes() {
        XCTAssertEqual(ValueFormat.minutes(60), "60 分钟")
    }
}
