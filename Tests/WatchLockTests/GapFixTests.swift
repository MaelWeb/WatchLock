import CoreBluetooth
import XCTest
@testable import WatchLock

/// 未绑定时不接受任何真实设备的样本（防止邻居的 Apple 设备驱动本机锁屏 / 亮屏）。
final class BoundSampleTests: XCTestCase {
    func testUnboundRejectsEverySample() {
        XCTAssertFalse(WatchMatcher.isBoundSample(boundIdentifier: nil, sampleIdentifier: UUID()))
    }

    func testBoundAcceptsOnlyExactIdentifier() {
        let bound = UUID()
        XCTAssertTrue(WatchMatcher.isBoundSample(boundIdentifier: bound.uuidString, sampleIdentifier: bound))
        XCTAssertFalse(WatchMatcher.isBoundSample(boundIdentifier: bound.uuidString, sampleIdentifier: UUID()))
    }

    func testMalformedBoundIdentifierRejectsSample() {
        XCTAssertFalse(WatchMatcher.isBoundSample(boundIdentifier: "not-a-uuid", sampleIdentifier: UUID()))
    }
}

/// 蓝牙不可用期间的转换规则：不可用不等于手表离开。
final class BluetoothOutageTests: XCTestCase {
    func testUnavailableStates() {
        for state in [CBManagerState.poweredOff, .unauthorized, .unsupported, .resetting] {
            XCTAssertTrue(BluetoothOutage.isUnavailable(state), "\(state.title)")
        }
        XCTAssertFalse(BluetoothOutage.isUnavailable(.poweredOn))
        XCTAssertFalse(BluetoothOutage.isUnavailable(.unknown))
    }

    func testBeginAndEndTransitions() {
        XCTAssertEqual(BluetoothOutage.transition(wasUnavailable: false, state: .poweredOff), .began)
        XCTAssertEqual(BluetoothOutage.transition(wasUnavailable: false, state: .resetting), .began)
        XCTAssertEqual(BluetoothOutage.transition(wasUnavailable: true, state: .poweredOn), .ended)
    }

    func testNoTransitionWhenStateUnchanged() {
        XCTAssertEqual(BluetoothOutage.transition(wasUnavailable: false, state: .poweredOn), .none)
        XCTAssertEqual(BluetoothOutage.transition(wasUnavailable: true, state: .poweredOff), .none)
        // 故障原因变化（关闭 → 重置）不是新的故障。
        XCTAssertEqual(BluetoothOutage.transition(wasUnavailable: true, state: .resetting), .none)
    }

    func testUnknownNeverChangesOutageState() {
        XCTAssertEqual(BluetoothOutage.transition(wasUnavailable: false, state: .unknown), .none)
        XCTAssertEqual(BluetoothOutage.transition(wasUnavailable: true, state: .unknown), .none)
    }

    func testNotificationBodyNamesCauseAndEffect() {
        let off = BluetoothOutage.notificationBody(for: .poweredOff)
        XCTAssertTrue(off.contains("蓝牙已关闭"))
        XCTAssertTrue(off.contains("自动锁定已暂停"))
        XCTAssertTrue(BluetoothOutage.notificationBody(for: .unauthorized).contains("权限"))
    }
}

final class LastLockSummaryTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private let locale = Locale(identifier: "en_US_POSIX")

    private func date(_ day: Int, hour: Int, minute: Int) -> Date {
        let components = DateComponents(
            calendar: calendar, timeZone: calendar.timeZone,
            year: 2026, month: 10, day: day, hour: hour, minute: minute
        )
        return calendar.date(from: components)!
    }

    func testSameDayShowsTimeOnly() {
        let text = LastLockSummary.text(
            reason: "手表离开设定范围",
            at: date(19, hour: 9, minute: 5),
            now: date(19, hour: 18, minute: 0),
            calendar: calendar,
            locale: locale
        )
        XCTAssertTrue(text.hasSuffix(" · 手表离开设定范围"))
        XCTAssertFalse(text.contains("Oct"))
        XCTAssertTrue(text.contains("9:05"))
    }

    func testPreviousDayIncludesDate() {
        let text = LastLockSummary.text(
            reason: "手动锁定",
            at: date(18, hour: 23, minute: 30),
            now: date(19, hour: 8, minute: 0),
            calendar: calendar,
            locale: locale
        )
        XCTAssertTrue(text.contains("Oct"))
        XCTAssertTrue(text.hasSuffix(" · 手动锁定"))
    }
}
