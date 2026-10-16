import XCTest
@testable import WatchLock

/// UI 层纯逻辑的单测：阈值 clamp、信号分级、刻度带换算。
/// 这些是界面正确性的关键约束（见 `.codebuddy/rules/watchlock-ui.md` §4）。
final class UIComponentTests: XCTestCase {

    // MARK: - 阈值 clamp

    func testClampKeepsValidPairUnchanged() {
        let result = ThresholdMath.clamp(near: -55, far: -70)
        XCTAssertEqual(result.near, -55)
        XCTAssertEqual(result.far, -70)
    }

    func testClampFixesReversedPair() {
        // 用户把「在身边」设得比「已离开」还弱 —— 必须被纠正。
        let result = ThresholdMath.clamp(near: -70, far: -55)
        XCTAssertGreaterThanOrEqual(result.near - result.far, ThresholdMath.minimumGap)
    }

    func testClampEnforcesMinimumGap() {
        let result = ThresholdMath.clamp(near: -60, far: -58)
        XCTAssertEqual(result.near, -60)
        XCTAssertEqual(result.far, -65)
    }

    func testClampRespectsRanges() {
        XCTAssertEqual(ThresholdMath.clamp(near: -120, far: -130).near, -90)
        XCTAssertEqual(ThresholdMath.clamp(near: -120, far: -130).far, -100)
        XCTAssertEqual(ThresholdMath.clamp(near: -30, far: -20).near, -35)
        XCTAssertEqual(ThresholdMath.clamp(near: -30, far: -20).far, -50)
    }

    func testClampHandlesLowerBoundary() {
        // 「已离开」触到量程下限时，应回头抬高「在身边」而不是产出非法组合。
        let result = ThresholdMath.clamp(near: -90, far: -91)
        XCTAssertEqual(result.near, -90)
        XCTAssertEqual(result.far, -95)
    }

    func testClampAlwaysProducesLegalPair() {
        for near in stride(from: -110, through: -20, by: 3) {
            for far in stride(from: -110, through: -20, by: 3) {
                let result = ThresholdMath.clamp(near: near, far: far)
                XCTAssertTrue(ThresholdMath.nearRange.contains(result.near), "near 越界：\(result)")
                XCTAssertTrue(ThresholdMath.farRange.contains(result.far), "far 越界：\(result)")
                XCTAssertGreaterThanOrEqual(result.near - result.far, ThresholdMath.minimumGap, "间隔不足：\(result)")
            }
        }
    }

    // MARK: - 刻度带换算

    func testFractionEndpoints() {
        XCTAssertEqual(ThresholdMath.fraction(ThresholdMath.bandRange.lowerBound), 0, accuracy: 0.001)
        XCTAssertEqual(ThresholdMath.fraction(ThresholdMath.bandRange.upperBound), 1, accuracy: 0.001)
    }

    func testFractionMidpoint() {
        let mid = (ThresholdMath.bandRange.lowerBound + ThresholdMath.bandRange.upperBound) / 2
        XCTAssertEqual(ThresholdMath.fraction(mid), 0.5, accuracy: 0.02)
    }

    func testValueRoundTrip() {
        for value in stride(from: -100, through: -35, by: 5) {
            XCTAssertEqual(ThresholdMath.value(fraction: ThresholdMath.fraction(value)), value)
        }
    }

    func testValueClampsOutOfRangeFraction() {
        XCTAssertEqual(ThresholdMath.value(fraction: -1), ThresholdMath.bandRange.lowerBound)
        XCTAssertEqual(ThresholdMath.value(fraction: 2), ThresholdMath.bandRange.upperBound)
    }

    // MARK: - 信号分级

    func testLevelUsesThresholdsNotFixedBands() {
        // 同一 RSSI 在不同阈值下应给出不同格数 —— 这正是「看到的格数 = 会不会锁屏」的含义。
        XCTAssertEqual(SignalMeter.level(rssi: -60, nearRSSI: -55, farRSSI: -70), 3)
        XCTAssertEqual(SignalMeter.level(rssi: -60, nearRSSI: -75, farRSSI: -90), 4)
    }

    func testLevelBoundaries() {
        XCTAssertEqual(SignalMeter.level(rssi: -55, nearRSSI: -55, farRSSI: -70), 4)
        XCTAssertEqual(SignalMeter.level(rssi: -63, nearRSSI: -55, farRSSI: -70), 2)
        XCTAssertEqual(SignalMeter.level(rssi: -75, nearRSSI: -55, farRSSI: -70), 1)
    }

    func testLevelTreatsInvalidRSSIAsNoSignal() {
        // macOS 拿不到信号强度时会回传 127，必须按「无信号」处理。
        XCTAssertEqual(SignalMeter.level(rssi: 127, nearRSSI: -55, farRSSI: -70), 0)
        XCTAssertEqual(SignalMeter.level(rssi: 0, nearRSSI: -55, farRSSI: -70), 0)
    }

    func testLevelNeverExceedsLevelCount() {
        for rssi in stride(from: -100, through: 0, by: 1) {
            let level = SignalMeter.level(rssi: Double(rssi), nearRSSI: -55, farRSSI: -70)
            XCTAssertTrue((0 ... SignalMeter.levelCount).contains(level))
        }
    }
}
