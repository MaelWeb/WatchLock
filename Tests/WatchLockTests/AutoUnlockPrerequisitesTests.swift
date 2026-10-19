import XCTest
@testable import WatchLock

final class AutoUnlockPrerequisitesTests: XCTestCase {
    func testParsesAllDocumentedSysadminctlOutputs() {
        XCTAssertEqual(ScreenLockDelay.parse("2026-10-19 sysadminctl[1:2] screenLock delay is immediate\n"), .immediate)
        XCTAssertEqual(ScreenLockDelay.parse("screenLock is off"), .off)
        XCTAssertEqual(ScreenLockDelay.parse("screenLock delay is 300 seconds"), .seconds(300))
        XCTAssertEqual(ScreenLockDelay.parse("Unknown state for screenLock (foo)"), .unknown)
        XCTAssertEqual(ScreenLockDelay.parse(""), .unknown)
    }

    func testUnknownLockDelayNeverReportsMissing() {
        XCTAssertTrue(AutoUnlockPrerequisites.missing(lockDelay: .unknown, companion: .available).isEmpty)
    }

    func testImmediateAndCompanionAvailableReportsNothing() {
        XCTAssertTrue(AutoUnlockPrerequisites.missing(lockDelay: .immediate, companion: .available).isEmpty)
    }

    func testDelayedOrOffLockReportsScreenLockGuidance() {
        for delay in [ScreenLockDelay.off, .seconds(60)] {
            XCTAssertEqual(
                AutoUnlockPrerequisites.missing(lockDelay: delay, companion: .available),
                [AutoUnlockPrerequisites.screenLockGuidance]
            )
        }
    }

    func testUnavailableCompanionReportsCompanionGuidance() {
        XCTAssertEqual(
            AutoUnlockPrerequisites.missing(lockDelay: .immediate, companion: .unavailable("com.apple.LocalAuthentication#-1")),
            [AutoUnlockPrerequisites.companionGuidance]
        )
    }

    func testBothMissingReportsBoth() {
        XCTAssertEqual(
            AutoUnlockPrerequisites.missing(lockDelay: .off, companion: .unavailable("x")).count,
            2
        )
    }
}

final class UnlockPrerequisiteWiringTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var settings: SettingsStore!

    override func setUpWithError() throws {
        suiteName = "watchlock.prereq.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        settings = SettingsStore(defaults: defaults)
        settings.unlockStrategy = .systemAutoUnlock
        settings.notificationsEnabled = false
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testPrerequisitesAreCheckedOnlyWhenSessionIsLocked() {
        var evaluations = 0
        let locked = UnlockService(
            settings: settings,
            wakeDisplay: { true },
            isScreenLocked: { true },
            evaluatePrerequisites: { evaluations += 1; return [] }
        )
        locked.handleApproach(now: Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(evaluations, 1)

        evaluations = 0
        let unlocked = UnlockService(
            settings: settings,
            wakeDisplay: { true },
            isScreenLocked: { false },
            evaluatePrerequisites: { evaluations += 1; return [] }
        )
        unlocked.handleApproach(now: Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(evaluations, 0)
    }
}
