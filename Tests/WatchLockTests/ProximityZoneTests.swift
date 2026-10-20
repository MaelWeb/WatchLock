import XCTest
@testable import WatchLock

/// 信号分区的纯逻辑。
/// 分区必须和 `SignalMeter.level` / 判定引擎同口径（见 `.codebuddy/rules/watchlock-ui.md` §4）。
final class ProximityZoneTests: XCTestCase {

    func testZoneBoundariesMatchEngine() {
        // 引擎：smoothed >= near → 在身边；smoothed <= far → 已离开（两端都含）。
        XCTAssertEqual(ProximityZone.classify(rssi: -55, nearRSSI: -55, farRSSI: -70), .near)
        XCTAssertEqual(ProximityZone.classify(rssi: -70, nearRSSI: -55, farRSSI: -70), .far)
        XCTAssertEqual(ProximityZone.classify(rssi: -62, nearRSSI: -55, farRSSI: -70), .transition)
    }

    func testZoneFollowsThresholdsNotFixedBands() {
        // 同一 RSSI，阈值不同分区就不同 —— 与信号条同一原则。
        XCTAssertEqual(ProximityZone.classify(rssi: -60, nearRSSI: -55, farRSSI: -70), .transition)
        XCTAssertEqual(ProximityZone.classify(rssi: -60, nearRSSI: -75, farRSSI: -90), .near)
        XCTAssertEqual(ProximityZone.classify(rssi: -60, nearRSSI: -50, farRSSI: -58), .far)
    }

    func testZoneTreatsInvalidRSSIAsUnknown() {
        // macOS 拿不到信号强度时会回传 127，必须按「无信号」处理。
        XCTAssertEqual(ProximityZone.classify(rssi: 127, nearRSSI: -55, farRSSI: -70), .unknown)
        XCTAssertEqual(ProximityZone.classify(rssi: 0, nearRSSI: -55, farRSSI: -70), .unknown)
    }

    func testZoneAgreesWithSignalMeterLevelEverywhere() {
        for rssi in stride(from: -110, through: 10, by: 1) {
            let value = Double(rssi)
            let level = SignalMeter.level(rssi: value, nearRSSI: -55, farRSSI: -70)
            let zone = ProximityZone.classify(rssi: value, nearRSSI: -55, farRSSI: -70)
            switch level {
            case SignalMeter.levelCount: XCTAssertEqual(zone, .near, "rssi=\(rssi)")
            case 2, 3: XCTAssertEqual(zone, .transition, "rssi=\(rssi)")
            case 1: XCTAssertEqual(zone, .far, "rssi=\(rssi)")
            default: XCTAssertEqual(zone, .unknown, "rssi=\(rssi)")
            }
        }
    }

    func testZoneOrderingIsMonotonicWithSignal() {
        // 信号越强，分区只能单调地从 已离开 → 过渡 → 在身边，不能来回跳。
        let order: [ProximityZone] = [.far, .transition, .near]
        var lastIndex = 0
        for rssi in stride(from: -100, through: -30, by: 1) {
            let zone = ProximityZone.classify(rssi: Double(rssi), nearRSSI: -55, farRSSI: -70)
            guard let index = order.firstIndex(of: zone) else {
                XCTFail("有效 RSSI 不应是 unknown：\(rssi)")
                continue
            }
            XCTAssertGreaterThanOrEqual(index, lastIndex, "rssi=\(rssi) 分区倒退")
            lastIndex = index
        }
    }
}
