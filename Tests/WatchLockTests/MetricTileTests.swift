import XCTest
@testable import WatchLock

/// 菜单栏指标瓦片的读数换算：无效信号、距离未知、秒 / 分钟边界。
final class MetricTileTests: XCTestCase {

    // MARK: - 信号

    func testSignalShowsRoundedDBm() {
        let reading = MenuBarMetrics.signal(rssi: -48.4)
        XCTAssertEqual(reading.value, "-48")
        XCTAssertNotNil(reading.unit)
    }

    func testSignalTreatsNonNegativeAsNoReading() {
        // macOS 拿不到信号强度时会回传 127；0 同样不是有效 RSSI。
        XCTAssertEqual(MenuBarMetrics.signal(rssi: 127), .none)
        XCTAssertEqual(MenuBarMetrics.signal(rssi: 0), .none)
    }

    // MARK: - 距离

    func testDistanceKeepsOneDecimal() {
        XCTAssertEqual(MenuBarMetrics.distance(meters: 0.64).value, "0.6")
        XCTAssertEqual(MenuBarMetrics.distance(meters: 4.2).value, "4.2")
    }

    func testDistanceUnknownWhenNotPositive() {
        XCTAssertEqual(MenuBarMetrics.distance(meters: 0), .none)
        XCTAssertEqual(MenuBarMetrics.distance(meters: -1), .none)
    }

    // MARK: - 更新时间

    func testUpdatedWithoutTimestampHasNoReading() {
        XCTAssertEqual(MenuBarMetrics.updated(since: nil), .none)
    }

    func testUpdatedUsesSecondsBelowOneMinute() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(MenuBarMetrics.updated(since: now, now: now).value, "0")
        XCTAssertEqual(MenuBarMetrics.updated(since: now.addingTimeInterval(-12), now: now).value, "12")
        let boundary = MenuBarMetrics.updated(since: now.addingTimeInterval(-59), now: now)
        XCTAssertEqual(boundary.value, "59")
    }

    func testUpdatedSwitchesToMinutesAtSixtySeconds() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let sixty = MenuBarMetrics.updated(since: now.addingTimeInterval(-60), now: now)
        let seconds = MenuBarMetrics.updated(since: now.addingTimeInterval(-59), now: now)
        XCTAssertEqual(sixty.value, "1")
        XCTAssertNotEqual(sixty.unit, seconds.unit, "60 秒应换成分钟单位")
        // 向下取整：119 秒仍是 1 分钟。
        XCTAssertEqual(MenuBarMetrics.updated(since: now.addingTimeInterval(-119), now: now).value, "1")
        XCTAssertEqual(MenuBarMetrics.updated(since: now.addingTimeInterval(-120), now: now).value, "2")
    }

    func testUpdatedClampsFutureTimestampToZero() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(MenuBarMetrics.updated(since: now.addingTimeInterval(30), now: now).value, "0")
    }

    // MARK: - 朗读文案

    func testSpokenJoinsValueAndUnit() {
        XCTAssertEqual(MetricReading(value: "12", unit: "秒前").spoken, "12 秒前")
        XCTAssertEqual(MetricReading.none.spoken, "—")
    }
}
