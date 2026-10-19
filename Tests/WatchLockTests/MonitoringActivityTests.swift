import XCTest
@testable import WatchLock

final class MonitoringActivityTests: XCTestCase {
    private final class Token: NSObject {}

    private func makeActivity(begins: @escaping (ProcessInfo.ActivityOptions) -> Void = { _ in },
                              ends: @escaping () -> Void = {}) -> MonitoringActivity {
        MonitoringActivity(
            begin: { options, _ in
                begins(options)
                return Token()
            },
            end: { _ in ends() }
        )
    }

    func testStartAndStopAreIdempotent() {
        var begins = 0
        var ends = 0
        let activity = makeActivity(begins: { _ in begins += 1 }, ends: { ends += 1 })
        activity.start()
        activity.start()
        XCTAssertTrue(activity.isActive)
        XCTAssertEqual(begins, 1)
        activity.stop()
        activity.stop()
        XCTAssertFalse(activity.isActive)
        XCTAssertEqual(ends, 1)
    }

    func testSetRequiredFollowsDemand() {
        var begins = 0
        var ends = 0
        let activity = makeActivity(begins: { _ in begins += 1 }, ends: { ends += 1 })
        activity.setRequired(true)
        activity.setRequired(true)
        activity.setRequired(false)
        activity.setRequired(true)
        XCTAssertEqual(begins, 2)
        XCTAssertEqual(ends, 1)
        XCTAssertTrue(activity.isActive)
    }

    func testOptionsDoNotBlockIdleSystemSleep() {
        var captured: ProcessInfo.ActivityOptions?
        let activity = makeActivity(begins: { captured = $0 })
        activity.start()
        let options = try? XCTUnwrap(captured)
        XCTAssertEqual(options, .userInitiatedAllowingIdleSystemSleep)
        XCTAssertFalse(options?.contains(.idleSystemSleepDisabled) ?? true)
        XCTAssertFalse(options?.contains(.idleDisplaySleepDisabled) ?? true)
    }

    func testDeinitReleasesHeldActivity() {
        var ends = 0
        var activity: MonitoringActivity? = makeActivity(ends: { ends += 1 })
        activity?.start()
        activity = nil
        XCTAssertEqual(ends, 1)
    }
}
