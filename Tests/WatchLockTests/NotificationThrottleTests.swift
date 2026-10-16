import XCTest
@testable import WatchLock

/// 通知频率限制（FR-09：同一原因 5 分钟内最多 1 条）。
final class NotificationThrottleTests: XCTestCase {
    func testSameKeyIsThrottled() {
        var throttle = NotificationThrottle(interval: 300)
        let now = Date()
        XCTAssertTrue(throttle.shouldSend(key: "lock", now: now))
        XCTAssertFalse(throttle.shouldSend(key: "lock", now: now.addingTimeInterval(60)))
        XCTAssertFalse(throttle.shouldSend(key: "lock", now: now.addingTimeInterval(299)))
        XCTAssertTrue(throttle.shouldSend(key: "lock", now: now.addingTimeInterval(300)))
    }

    func testDifferentKeysAreIndependent() {
        var throttle = NotificationThrottle(interval: 300)
        let now = Date()
        XCTAssertTrue(throttle.shouldSend(key: "lock", now: now))
        XCTAssertTrue(throttle.shouldSend(key: "bluetooth", now: now))
    }

    func testRemainingCooldown() {
        var throttle = NotificationThrottle(interval: 300)
        let now = Date()
        XCTAssertEqual(throttle.remainingCooldown(key: "lock", now: now), 0)
        throttle.shouldSend(key: "lock", now: now)
        XCTAssertEqual(throttle.remainingCooldown(key: "lock", now: now.addingTimeInterval(100)), 200, accuracy: 0.001)
        XCTAssertEqual(throttle.remainingCooldown(key: "lock", now: now.addingTimeInterval(400)), 0)
    }

    func testReset() {
        var throttle = NotificationThrottle(interval: 300)
        let now = Date()
        throttle.shouldSend(key: "lock", now: now)
        throttle.reset()
        XCTAssertTrue(throttle.shouldSend(key: "lock", now: now))
    }
}
