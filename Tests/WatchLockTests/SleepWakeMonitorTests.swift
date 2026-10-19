import AppKit
import XCTest
@testable import WatchLock

final class SleepWakeMonitorTests: XCTestCase {
    private var workspace: NotificationCenter!
    private var distributed: NotificationCenter!
    private var monitor: SleepWakeMonitor!
    /// 注入的会话锁定探针结果；默认 nil，让既有测试不受真实系统状态影响。
    private var probeResult: Bool?
    private let locked = Notification.Name("com.apple.screenIsLocked")
    private let unlocked = Notification.Name("com.apple.screenIsUnlocked")

    override func setUpWithError() throws {
        workspace = NotificationCenter()
        distributed = NotificationCenter()
        probeResult = nil
        monitor = SleepWakeMonitor(workspace: workspace, distributed: distributed, sessionLockProbe: { [unowned self] in
            self.probeResult
        })
        monitor.start()
    }

    override func tearDownWithError() throws {
        monitor.stop()
        monitor = nil
        workspace = nil
        distributed = nil
    }

    private func post(_ name: Notification.Name, to center: NotificationCenter) {
        if Thread.isMainThread {
            center.post(name: name, object: nil)
        } else {
            DispatchQueue.main.sync { center.post(name: name, object: nil) }
        }
    }

    func testDisplaySleepDoesNotLockSession() {
        var displaySleepCount = 0
        var lockCount = 0
        monitor.onDisplaySleep = { displaySleepCount += 1 }
        monitor.onScreenLocked = { lockCount += 1 }
        post(NSWorkspace.screensDidSleepNotification, to: workspace)
        XCTAssertTrue(monitor.isDisplayAsleep)
        XCTAssertFalse(monitor.isScreenLocked)
        XCTAssertEqual(displaySleepCount, 1)
        XCTAssertEqual(lockCount, 0)
    }

    func testDisplayWakeDoesNotUnlockLockedSession() {
        var unlockCount = 0
        var displayWakeCount = 0
        monitor.onScreenUnlocked = { unlockCount += 1 }
        monitor.onDisplayWake = { displayWakeCount += 1 }
        post(locked, to: distributed)
        post(NSWorkspace.screensDidSleepNotification, to: workspace)
        post(NSWorkspace.screensDidWakeNotification, to: workspace)
        XCTAssertFalse(monitor.isDisplayAsleep)
        XCTAssertTrue(monitor.isScreenLocked)
        XCTAssertEqual(displayWakeCount, 1)
        XCTAssertEqual(unlockCount, 0)
        post(unlocked, to: distributed)
        XCTAssertFalse(monitor.isScreenLocked)
        XCTAssertEqual(unlockCount, 1)
    }

    func testSessionUnlockDoesNotImplyDisplayWake() {
        post(NSWorkspace.screensDidSleepNotification, to: workspace)
        post(locked, to: distributed)
        post(unlocked, to: distributed)
        XCTAssertTrue(monitor.isDisplayAsleep)
        XCTAssertFalse(monitor.isScreenLocked)
    }

    func testSystemSleepAndWakeRemainSeparateFromSessionLock() {
        post(locked, to: distributed)
        post(NSWorkspace.willSleepNotification, to: workspace)
        XCTAssertTrue(monitor.isSystemSleeping)
        XCTAssertTrue(monitor.isScreenLocked)
        post(NSWorkspace.didWakeNotification, to: workspace)
        XCTAssertFalse(monitor.isSystemSleeping)
        XCTAssertTrue(monitor.isScreenLocked)
    }

    func testCallbacksObserveUpdatedState() {
        monitor.onSleep = { XCTAssertTrue(self.monitor.isSystemSleeping) }
        monitor.onWake = { XCTAssertFalse(self.monitor.isSystemSleeping) }
        monitor.onScreenLocked = { XCTAssertTrue(self.monitor.isScreenLocked) }
        monitor.onScreenUnlocked = { XCTAssertFalse(self.monitor.isScreenLocked) }
        post(NSWorkspace.willSleepNotification, to: workspace)
        post(NSWorkspace.didWakeNotification, to: workspace)
        post(locked, to: distributed)
        post(unlocked, to: distributed)
    }

    func testStartIsIdempotentAndStopRemovesBothCenters() {
        var wakeCount = 0
        var lockCount = 0
        monitor.onDisplayWake = { wakeCount += 1 }
        monitor.onScreenLocked = { lockCount += 1 }
        monitor.start()
        post(NSWorkspace.screensDidWakeNotification, to: workspace)
        post(locked, to: distributed)
        XCTAssertEqual(wakeCount, 1)
        XCTAssertEqual(lockCount, 1)
        monitor.stop()
        post(NSWorkspace.screensDidSleepNotification, to: workspace)
        post(unlocked, to: distributed)
        XCTAssertFalse(monitor.isDisplayAsleep)
        XCTAssertTrue(monitor.isScreenLocked)
        monitor.start()
        post(NSWorkspace.screensDidWakeNotification, to: workspace)
        post(locked, to: distributed)
        XCTAssertEqual(wakeCount, 2)
        XCTAssertEqual(lockCount, 2)
    }

    // MARK: - 会话锁定状态校正

    func testRefreshCorrectsStuckLockedStateWhenUnlockNotificationWasMissed() {
        var unlockCount = 0
        monitor.onScreenUnlocked = { unlockCount += 1 }
        post(locked, to: distributed)
        XCTAssertTrue(monitor.isScreenLocked)
        probeResult = false
        XCTAssertFalse(monitor.refreshSessionLockState())
        XCTAssertFalse(monitor.isScreenLocked)
        XCTAssertEqual(unlockCount, 1)
    }

    func testRefreshCorrectsMissedLockNotification() {
        var lockCount = 0
        monitor.onScreenLocked = { lockCount += 1 }
        probeResult = true
        XCTAssertTrue(monitor.refreshSessionLockState())
        XCTAssertEqual(lockCount, 1)
    }

    func testRefreshKeepsStateWhenProbeCannotAnswer() {
        post(locked, to: distributed)
        probeResult = nil
        XCTAssertTrue(monitor.refreshSessionLockState())
        XCTAssertTrue(monitor.isScreenLocked)
    }

    func testRefreshDoesNotFireCallbacksWhenStateAgrees() {
        var calls = 0
        monitor.onScreenLocked = { calls += 1 }
        monitor.onScreenUnlocked = { calls += 1 }
        post(locked, to: distributed)
        calls = 0
        probeResult = true
        monitor.refreshSessionLockState()
        XCTAssertEqual(calls, 0)
    }

    func testSystemWakeResyncsSessionLockState() {
        post(locked, to: distributed)
        post(NSWorkspace.willSleepNotification, to: workspace)
        probeResult = false
        post(NSWorkspace.didWakeNotification, to: workspace)
        XCTAssertFalse(monitor.isScreenLocked)
    }

    func testStartSyncsInitialSessionLockState() {
        let center = NotificationCenter()
        let fresh = SleepWakeMonitor(workspace: center, distributed: center, sessionLockProbe: { true })
        fresh.start()
        XCTAssertTrue(fresh.isScreenLocked)
        fresh.stop()
    }

    func testSessionLockProbeInterpretsDictionary() {
        XCTAssertFalse(SessionLockProbe.isLocked(in: [:]))
        XCTAssertFalse(SessionLockProbe.isLocked(in: ["kCGSessionLoginDoneKey": 1]))
        XCTAssertTrue(SessionLockProbe.isLocked(in: [SessionLockProbe.lockedKey: true]))
        XCTAssertTrue(SessionLockProbe.isLocked(in: [SessionLockProbe.lockedKey: 1]))
        XCTAssertFalse(SessionLockProbe.isLocked(in: [SessionLockProbe.lockedKey: 0]))
        XCTAssertTrue(SessionLockProbe.isLocked(in: [SessionLockProbe.lockedKey: "yes"]))
    }
}
