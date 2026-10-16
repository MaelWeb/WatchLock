import XCTest
@testable import WatchLock

final class UnlockServiceTests: XCTestCase {
    private var suiteName: String = ""
    private var defaults: UserDefaults!
    private var settings: SettingsStore!
    private let now = Date(timeIntervalSince1970: 1_000)

    override func setUpWithError() throws {
        suiteName = "watchlock.unlock.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        settings = SettingsStore(defaults: defaults)
        settings.unlockStrategy = .wakeOnly
        settings.notificationsEnabled = false
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        settings = nil
        defaults = nil
    }

    func testApproachRequestsWakeWhileSessionLocked() {
        var calls = 0
        let service = UnlockService(settings: settings, wakeDisplay: {
            calls += 1
            return true
        }, isScreenLocked: { true })
        service.handleApproach(now: now)
        XCTAssertEqual(calls, 1)
    }

    func testApproachAlsoWakesDisplayWithoutSessionLock() {
        var calls = 0
        let service = UnlockService(settings: settings, wakeDisplay: {
            calls += 1
            return true
        }, isScreenLocked: { false })
        service.handleApproach(now: now)
        XCTAssertEqual(calls, 1)
    }

    func testWakeToggleOffBlocksApproach() {
        settings.wakeDisplayOnApproach = false
        let service = UnlockService(settings: settings, wakeDisplay: {
            XCTFail("Wake must remain disabled")
            return true
        })
        service.handleApproach(now: now)
    }

    func testDisabledAndPausedBlockApproach() {
        let service = UnlockService(settings: settings, wakeDisplay: {
            XCTFail("Disabled or paused applications must not wake the display")
            return true
        })
        settings.isEnabled = false
        service.handleApproach(now: now)
        settings.isEnabled = true
        settings.pause(minutes: 15)
        service.handleApproach(now: now)
    }

    func testCooldownDefersNewApproachUntilFreshNearSample() {
        var calls = 0
        let service = UnlockService(settings: settings, wakeDisplay: {
            calls += 1
            return true
        })
        service.handleApproach(now: now)
        service.handleApproach(now: now.addingTimeInterval(1))
        service.retryPendingApproach(now: now.addingTimeInterval(9))
        XCTAssertEqual(calls, 1)
        service.retryPendingApproach(now: now.addingTimeInterval(10))
        service.retryPendingApproach(now: now.addingTimeInterval(20))
        XCTAssertEqual(calls, 2)
    }

    func testFailedWakeGetsOneRetryAfterCooldown() {
        var calls = 0
        let service = UnlockService(settings: settings, wakeDisplay: {
            calls += 1
            return calls > 1
        })
        service.handleApproach(now: now)
        service.retryPendingApproach(now: now.addingTimeInterval(9))
        XCTAssertEqual(calls, 1)
        service.retryPendingApproach(now: now.addingTimeInterval(10))
        service.retryPendingApproach(now: now.addingTimeInterval(20))
        XCTAssertEqual(calls, 2)
    }

    func testRepeatedFailureDoesNotCreateUnlimitedRetries() {
        var calls = 0
        let service = UnlockService(settings: settings, wakeDisplay: {
            calls += 1
            return false
        })
        service.handleApproach(now: now)
        for offset in [10.0, 20.0, 30.0] {
            service.retryPendingApproach(now: now.addingTimeInterval(offset))
        }
        XCTAssertEqual(calls, 2)
    }

    func testSuccessfulWakeDoesNotRetryForContinuousNearSamples() {
        var calls = 0
        let service = UnlockService(settings: settings, wakeDisplay: {
            calls += 1
            return true
        })
        service.handleApproach(now: now)
        service.retryPendingApproach(now: now.addingTimeInterval(30))
        XCTAssertEqual(calls, 1)
    }

    func testCancelPendingApproachPreventsRetryAfterLeavingOrSleeping() {
        var calls = 0
        let service = UnlockService(settings: settings, wakeDisplay: {
            calls += 1
            return false
        })
        service.handleApproach(now: now)
        service.cancelPendingApproach()
        service.retryPendingApproach(now: now.addingTimeInterval(10))
        XCTAssertEqual(calls, 1)
    }

    func testDisablingWakeCancelsPendingRetry() {
        var calls = 0
        let service = UnlockService(settings: settings, wakeDisplay: {
            calls += 1
            return false
        })
        service.handleApproach(now: now)
        settings.wakeDisplayOnApproach = false
        service.retryPendingApproach(now: now.addingTimeInterval(10))
        settings.wakeDisplayOnApproach = true
        service.retryPendingApproach(now: now.addingTimeInterval(20))
        XCTAssertEqual(calls, 1)
    }

    func testManagedPasswordIsNotReadWhenSessionIsUnlocked() {
        settings.unlockStrategy = .managedPassword
        var checks = 0
        let service = UnlockService(settings: settings, wakeDisplay: { true }, isScreenLocked: {
            checks += 1
            return false
        })
        service.handleApproach(now: now)
        XCTAssertEqual(checks, 1)
    }
}
