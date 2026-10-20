import XCTest
@testable import WatchLock

/// 距离刻度的纯逻辑：分区、指针位置。
/// 分区必须和 `SignalMeter.level` / 判定引擎同口径（见 `.codebuddy/rules/watchlock-ui.md` §4）。
final class ProximityGaugeTests: XCTestCase {

    // MARK: - 分区

    func testZoneBoundariesMatchEngine() {
        // 引擎：smoothed >= near → 在身边；smoothed <= far → 已离开（两端都含）。
        XCTAssertEqual(ProximityGaugeMath.zone(rssi: -55, nearRSSI: -55, farRSSI: -70), .near)
        XCTAssertEqual(ProximityGaugeMath.zone(rssi: -70, nearRSSI: -55, farRSSI: -70), .far)
        XCTAssertEqual(ProximityGaugeMath.zone(rssi: -62, nearRSSI: -55, farRSSI: -70), .transition)
    }

    func testZoneFollowsThresholdsNotFixedBands() {
        // 同一 RSSI，阈值不同分区就不同 —— 与信号条同一原则。
        XCTAssertEqual(ProximityGaugeMath.zone(rssi: -60, nearRSSI: -55, farRSSI: -70), .transition)
        XCTAssertEqual(ProximityGaugeMath.zone(rssi: -60, nearRSSI: -75, farRSSI: -90), .near)
        XCTAssertEqual(ProximityGaugeMath.zone(rssi: -60, nearRSSI: -50, farRSSI: -58), .far)
    }

    func testZoneTreatsInvalidRSSIAsUnknown() {
        // macOS 拿不到信号强度时会回传 127，必须按「无信号」处理。
        XCTAssertEqual(ProximityGaugeMath.zone(rssi: 127, nearRSSI: -55, farRSSI: -70), .unknown)
        XCTAssertEqual(ProximityGaugeMath.zone(rssi: 0, nearRSSI: -55, farRSSI: -70), .unknown)
    }

    func testZoneAgreesWithSignalMeterLevelEverywhere() {
        for rssi in stride(from: -110, through: 10, by: 1) {
            let value = Double(rssi)
            let level = SignalMeter.level(rssi: value, nearRSSI: -55, farRSSI: -70)
            let zone = ProximityGaugeMath.zone(rssi: value, nearRSSI: -55, farRSSI: -70)
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
            let zone = ProximityGaugeMath.zone(rssi: Double(rssi), nearRSSI: -55, farRSSI: -70)
            guard let index = order.firstIndex(of: zone) else {
                XCTFail("有效 RSSI 不应是 unknown：\(rssi)")
                continue
            }
            XCTAssertGreaterThanOrEqual(index, lastIndex, "rssi=\(rssi) 分区倒退")
            lastIndex = index
        }
    }

    // MARK: - 指针位置

    func testNeedleHiddenForInvalidRSSI() {
        XCTAssertNil(ProximityGaugeMath.needleFraction(rssi: 127))
        XCTAssertNil(ProximityGaugeMath.needleFraction(rssi: 0))
    }

    func testNeedleEndpointsAndClamping() throws {
        let lower = Double(ThresholdMath.bandRange.lowerBound)
        let upper = Double(ThresholdMath.bandRange.upperBound)
        XCTAssertEqual(try XCTUnwrap(ProximityGaugeMath.needleFraction(rssi: lower)), 0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(ProximityGaugeMath.needleFraction(rssi: upper)), 1, accuracy: 0.001)
        // 超出量程时贴边，不越界。
        XCTAssertEqual(try XCTUnwrap(ProximityGaugeMath.needleFraction(rssi: -120)), 0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(ProximityGaugeMath.needleFraction(rssi: -10)), 1, accuracy: 0.001)
    }

    func testNeedleSharesAxisWithThresholdBand() throws {
        // 指针和阈值在同一根轴上：RSSI 恰等于阈值时，指针必须正好落在分区边界上。
        let atNear = try XCTUnwrap(ProximityGaugeMath.needleFraction(rssi: -55))
        let atFar = try XCTUnwrap(ProximityGaugeMath.needleFraction(rssi: -70))
        XCTAssertEqual(atNear, ThresholdMath.fraction(-55), accuracy: 0.0001)
        XCTAssertEqual(atFar, ThresholdMath.fraction(-70), accuracy: 0.0001)
        XCTAssertGreaterThan(atNear, atFar)
    }

    // MARK: - 增强对比度

    func testDefaultOpacityKeepsOriginalLook() {
        // 默认值必须与改版时设计稿（mockups.css .gauge）一致：38% / 26% / 12%。
        let normal = ProximityGaugeMath.opacity(increasedContrast: false)
        XCTAssertEqual(normal, .init(zone: 0.38, idle: 0.26, track: 0.12))
    }

    func testIncreasedContrastDeepensEveryLayer() {
        let normal = ProximityGaugeMath.opacity(increasedContrast: false)
        let increased = ProximityGaugeMath.opacity(increasedContrast: true)
        XCTAssertGreaterThan(increased.zone, normal.zone)
        XCTAssertGreaterThan(increased.idle, normal.idle)
        XCTAssertGreaterThan(increased.track, normal.track)
    }

    func testIdleStaysQuieterThanArmedZonesInBothModes() {
        // 分区转灰（不会自动锁）时，视觉权重必须始终低于会锁定的状态，否则「转灰」就失去意义。
        for increased in [false, true] {
            let value = ProximityGaugeMath.opacity(increasedContrast: increased)
            XCTAssertLessThan(value.idle, value.zone, "increased=\(increased)")
            XCTAssertLessThan(value.track, value.idle, "increased=\(increased)")
            XCTAssertLessThanOrEqual(value.zone, 1)
        }
    }
}
