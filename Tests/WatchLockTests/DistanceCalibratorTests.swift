import XCTest
@testable import WatchLock

/// 距离校准计算（FR-14）。
final class DistanceCalibratorTests: XCTestCase {
    func testMedian() {
        XCTAssertEqual(DistanceCalibrator.median([-70, -50, -60]), -60)
        XCTAssertEqual(DistanceCalibrator.median([-52, -50]), -51)
        XCTAssertEqual(DistanceCalibrator.median([-55]), -55)
        XCTAssertNil(DistanceCalibrator.median([]))
    }

    func testMeasuredPowerUsesMedian() {
        let value = DistanceCalibrator.measuredPower(samples: [-54, -56, -55], fallback: -55)
        XCTAssertEqual(value, -55)
    }

    func testMeasuredPowerFallsBackWhenNoSamples() {
        XCTAssertEqual(DistanceCalibrator.measuredPower(samples: [], fallback: -59), -59)
    }

    func testMeasuredPowerIsClamped() {
        XCTAssertEqual(DistanceCalibrator.measuredPower(samples: [-20], fallback: -55), -30)
        XCTAssertEqual(DistanceCalibrator.measuredPower(samples: [-120], fallback: -55), -90)
    }

    /// 绑定后自动校准：把绑定那一刻的信号当作「在身边」基准。
    func testAutoThresholdsAfterBinding() {
        let samples = Array(repeating: -72, count: 8) + [-71, -73]
        let result = DistanceCalibrator.autoThresholds(
            from: samples,
            fallback: .init(nearRSSI: -55, farRSSI: -70, measuredPower: -55)
        )
        XCTAssertEqual(result.measuredPower, -72)
        XCTAssertEqual(result.nearRSSI, -77)
        XCTAssertEqual(result.farRSSI, -94)
        XCTAssertGreaterThanOrEqual(result.nearRSSI - result.farRSSI, 10)
        // 手表就在旁边（约 -72）必须判定为「在身边」
        XCTAssertGreaterThanOrEqual(-72, result.nearRSSI)
    }

    func testAutoThresholdsFallbackWhenTooFewSamples() {
        let fallback = DistanceCalibrator.AutoResult(nearRSSI: -55, farRSSI: -70, measuredPower: -55)
        XCTAssertEqual(
            DistanceCalibrator.autoThresholds(from: [-72, -73], fallback: fallback),
            fallback
        )
    }

    func testAutoThresholdsIsClamped() {
        let result = DistanceCalibrator.autoThresholds(
            from: Array(repeating: -30, count: 10),
            fallback: .init(nearRSSI: -55, farRSSI: -70, measuredPower: -55)
        )
        XCTAssertEqual(result.nearRSSI, -35)
        XCTAssertGreaterThanOrEqual(result.farRSSI, -100)
    }

    func testTwoPointThresholds() {
        let result = DistanceCalibrator.thresholds(
            nearSamples: [-50, -52, -50],
            farSamples: [-74, -76, -75],
            fallback: .init(nearRSSI: -55, farRSSI: -70)
        )
        XCTAssertEqual(result.nearRSSI, -53)
        XCTAssertEqual(result.farRSSI, -72)
        // 采样点必须能被正确分类
        XCTAssertGreaterThanOrEqual(DistanceCalibrator.median([-50, -52, -50])!, result.nearRSSI)
        XCTAssertLessThanOrEqual(DistanceCalibrator.median([-74, -76, -75])!, result.farRSSI)
        XCTAssertGreaterThan(result.nearRSSI, result.farRSSI)
    }

    func testTwoPointThresholdsFallbackWhenIncomplete() {
        let fallback = DistanceCalibrator.Thresholds(nearRSSI: -55, farRSSI: -70)
        XCTAssertEqual(
            DistanceCalibrator.thresholds(nearSamples: [], farSamples: [-75], fallback: fallback),
            fallback
        )
        XCTAssertEqual(
            DistanceCalibrator.thresholds(nearSamples: [-50], farSamples: [], fallback: fallback),
            fallback
        )
    }

    func testTwoPointThresholdsKeepMinimumGap() {
        let result = DistanceCalibrator.thresholds(
            nearSamples: [-60],
            farSamples: [-62],
            fallback: .init(nearRSSI: -55, farRSSI: -70)
        )
        XCTAssertGreaterThanOrEqual(result.nearRSSI - result.farRSSI, 8)
        XCTAssertLessThanOrEqual(result.nearRSSI, -35)
        XCTAssertGreaterThanOrEqual(result.farRSSI, -100)
    }
}
