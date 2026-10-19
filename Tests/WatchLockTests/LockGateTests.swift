import XCTest
@testable import WatchLock

/// 断言表解析：数据结构取自 macOS 26.6.1 上 `IOPMCopyAssertionsByProcess` 的实测输出。
final class MeetingExemptionTests: XCTestCase {
    private func assertion(
        type: String,
        trueType: String? = nil,
        name: String,
        process: String,
        level: Int = 255
    ) -> [String: Any] {
        var dict: [String: Any] = [
            "AssertType": type,
            "AssertName": name,
            "Process Name": process,
            "AssertLevel": level
        ]
        if let trueType { dict["AssertionTrueType"] = trueType }
        return dict
    }

    func testPicksDisplaySleepHolders() {
        let raw: [NSNumber: [[String: Any]]] = [
            100: [assertion(type: "PreventUserIdleDisplaySleep", name: "Meeting", process: "zoom.us")],
            200: [assertion(type: "PreventUserIdleSystemSleep", name: "x", process: "other")]
        ]
        let holders = MeetingExemption.holders(from: raw, ownPID: 1)
        XCTAssertEqual(holders, [DisplaySleepHolder(pid: 100, processName: "zoom.us", assertionName: "Meeting")])
    }

    func testIgnoresPowerdInternalAssertionAndCaffeinate() {
        let raw: [NSNumber: [[String: Any]]] = [
            537: [assertion(type: "InternalPreventDisplaySleep", name: "delayDisplayOff", process: "powerd")],
            300: [assertion(type: "PreventUserIdleDisplaySleep", name: "caffeinate command-line tool", process: "caffeinate")]
        ]
        XCTAssertTrue(MeetingExemption.holders(from: raw, ownPID: 1).isEmpty)
    }

    func testLegacyNoDisplaySleepAssertionIsRecognisedViaTrueType() {
        let raw: [NSNumber: [[String: Any]]] = [
            100: [assertion(type: "NoDisplaySleepAssertion", trueType: "PreventUserIdleDisplaySleep", name: "old", process: "Keynote")]
        ]
        XCTAssertEqual(MeetingExemption.holders(from: raw, ownPID: 1).map(\.processName), ["Keynote"])
    }

    func testIgnoresOwnProcessAndReleasedAssertions() {
        let raw: [NSNumber: [[String: Any]]] = [
            7: [assertion(type: "PreventUserIdleDisplaySleep", name: "mine", process: "someapp")],
            8: [assertion(type: "PreventUserIdleDisplaySleep", name: "off", process: "player", level: 0)]
        ]
        XCTAssertTrue(MeetingExemption.holders(from: raw, ownPID: 7).isEmpty)
    }

    func testDecisionMatrix() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let holder = [DisplaySleepHolder(pid: 1, processName: "zoom.us", assertionName: "")]
        func decide(enabled: Bool, holders: [DisplaySleepHolder], since: Date?, now: TimeInterval) -> MeetingExemption.Decision {
            MeetingExemption.decide(enabled: enabled, holders: holders, deferredSince: since,
                                    now: t0.addingTimeInterval(now), maxDeferral: 600)
        }
        XCTAssertEqual(decide(enabled: false, holders: holder, since: nil, now: 0), .lockNow)
        XCTAssertEqual(decide(enabled: true, holders: [], since: nil, now: 0), .lockNow)
        XCTAssertEqual(decide(enabled: true, holders: holder, since: nil, now: 0), .deferLock)
        XCTAssertEqual(decide(enabled: true, holders: holder, since: t0, now: 599), .deferLock)
        XCTAssertEqual(decide(enabled: true, holders: holder, since: t0, now: 600), .lockCapped)
    }
}

final class LockGateTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 10_000)
    private var holders: [DisplaySleepHolder] = []
    private var idle: TimeInterval? = 0
    private var config = LockGate.Config()

    private let meeting = [DisplaySleepHolder(pid: 1, processName: "zoom.us", assertionName: "")]

    private func makeGate() -> LockGate {
        LockGate(
            config: { [unowned self] in self.config },
            holders: { [unowned self] in self.holders },
            idleSeconds: { [unowned self] in self.idle },
            now: { [unowned self] in self.clock }
        )
    }

    private func advance(_ seconds: TimeInterval) { clock = clock.addingTimeInterval(seconds) }

    // MARK: 默认行为不变

    func testDefaultsLockImmediatelyEvenWithMeetingHolder() {
        holders = meeting
        let gate = makeGate()
        XCTAssertEqual(gate.request(reason: "r"), LockGate.Grant(reason: "r", isRearm: false))
        XCTAssertFalse(gate.isDeferring)
    }

    func testRearmDisabledByDefault() {
        let gate = makeGate()
        gate.screenUnlocked(watchIsFar: true)
        XCTAssertFalse(gate.isRearmArmed)
    }

    // MARK: 会议豁免

    func testDefersWhileMeetingThenLocksWhenItEnds() {
        config.meetingExemptionEnabled = true
        holders = meeting
        let gate = makeGate()
        XCTAssertNil(gate.request(reason: "手表离开"))
        XCTAssertTrue(gate.isDeferring)
        XCTAssertNotNil(gate.deferralNote)

        advance(30)
        XCTAssertNil(gate.tick(watchIsFar: true))

        holders = []
        advance(1)
        let grant = gate.tick(watchIsFar: true)
        XCTAssertEqual(grant?.reason, "手表离开（会议 / 演示结束后）")
        XCTAssertEqual(grant?.isRearm, false)
        XCTAssertFalse(gate.isDeferring)
        XCTAssertNil(gate.deferralNote)
    }

    func testDeferralIsCappedAndThenLocksEvenIfMeetingContinues() {
        config.meetingExemptionEnabled = true
        config.maxDeferral = 600
        holders = meeting
        let gate = makeGate()
        XCTAssertNil(gate.request(reason: "r"))
        advance(599)
        XCTAssertNil(gate.tick(watchIsFar: true))
        advance(1)
        let grant = gate.tick(watchIsFar: true)
        XCTAssertEqual(grant?.reason, "r（已暂缓满上限）")
        XCTAssertFalse(gate.isDeferring)
    }

    func testWatchReturningCancelsDeferral() {
        config.meetingExemptionEnabled = true
        holders = meeting
        let gate = makeGate()
        XCTAssertNil(gate.request(reason: "r"))
        XCTAssertNil(gate.tick(watchIsFar: false))
        XCTAssertFalse(gate.isDeferring)
        holders = []
        XCTAssertNil(gate.tick(watchIsFar: true), "取消后不应再补锁")
    }

    func testSecondRequestWhileDeferringDoesNotRestartTheCap() {
        config.meetingExemptionEnabled = true
        config.maxDeferral = 600
        holders = meeting
        let gate = makeGate()
        XCTAssertNil(gate.request(reason: "r"))
        advance(500)
        XCTAssertNil(gate.request(reason: "r"))
        advance(100)
        XCTAssertNotNil(gate.tick(watchIsFar: true), "上限应从第一次暂缓起算")
    }

    func testDisablingTheOptionWhileDeferringLocksOnNextTick() {
        config.meetingExemptionEnabled = true
        holders = meeting
        let gate = makeGate()
        XCTAssertNil(gate.request(reason: "r"))
        config.meetingExemptionEnabled = false
        XCTAssertNotNil(gate.tick(watchIsFar: true))
    }

    func testCancelClearsEverything() {
        config.meetingExemptionEnabled = true
        config.rearmEnabled = true
        holders = meeting
        let gate = makeGate()
        XCTAssertNil(gate.request(reason: "r"))
        gate.screenUnlocked(watchIsFar: true)
        gate.cancel()
        XCTAssertFalse(gate.isDeferring)
        XCTAssertFalse(gate.isRearmArmed)
    }

    // MARK: 手动解锁后重新布防

    func testRearmLocksOnlyAfterIdleThreshold() {
        config.rearmEnabled = true
        config.rearmIdle = 300
        let gate = makeGate()
        gate.screenUnlocked(watchIsFar: true)
        XCTAssertTrue(gate.isRearmArmed)

        idle = 299
        XCTAssertNil(gate.tick(watchIsFar: true))
        idle = 300
        let grant = gate.tick(watchIsFar: true)
        XCTAssertEqual(grant?.isRearm, true)
        XCTAssertFalse(gate.isRearmArmed)
    }

    func testRearmNotArmedWhenWatchIsNear() {
        config.rearmEnabled = true
        let gate = makeGate()
        gate.screenUnlocked(watchIsFar: false)
        XCTAssertFalse(gate.isRearmArmed)
    }

    func testRearmDisarmsWhenWatchComesBack() {
        config.rearmEnabled = true
        let gate = makeGate()
        gate.screenUnlocked(watchIsFar: true)
        idle = 10_000
        XCTAssertNil(gate.tick(watchIsFar: false))
        XCTAssertFalse(gate.isRearmArmed)
    }

    func testRearmKeepsWaitingWhenIdleUnknown() {
        config.rearmEnabled = true
        let gate = makeGate()
        gate.screenUnlocked(watchIsFar: true)
        idle = nil
        XCTAssertNil(gate.tick(watchIsFar: true))
        XCTAssertTrue(gate.isRearmArmed, "查不到空闲时长时宁可不锁，也不凭空锁屏")
    }

    func testRearmedLockIsStillSubjectToMeetingExemption() {
        config.rearmEnabled = true
        config.meetingExemptionEnabled = true
        holders = meeting
        let gate = makeGate()
        gate.screenUnlocked(watchIsFar: true)
        idle = 10_000
        XCTAssertNil(gate.tick(watchIsFar: true))
        XCTAssertTrue(gate.isDeferring)
        holders = []
        let grant = gate.tick(watchIsFar: true)
        XCTAssertEqual(grant?.isRearm, true, "补锁仍属于重新布防，不应计入误锁样本")
    }
}

final class LockGateSettingsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "watchlock.gate.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testBothOptionsDefaultToOff() {
        let settings = SettingsStore(defaults: defaults)
        XCTAssertFalse(settings.meetingExemptionEnabled)
        XCTAssertFalse(settings.rearmAfterManualUnlock)
        XCTAssertEqual(settings.lockGateConfig.maxDeferral, 3600)
        XCTAssertEqual(settings.lockGateConfig.rearmIdle, 300)
    }

    func testPersistsAndClampsOutOfRangeValues() {
        let settings = SettingsStore(defaults: defaults)
        settings.meetingExemptionEnabled = true
        settings.meetingMaxDeferralMinutes = 100_000
        settings.rearmIdleMinutes = 0
        XCTAssertEqual(settings.lockGateConfig.maxDeferral, 240 * 60, "暂缓上限必须有硬顶")
        XCTAssertEqual(settings.lockGateConfig.rearmIdle, 60)

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertTrue(reloaded.meetingExemptionEnabled)
        XCTAssertEqual(reloaded.meetingMaxDeferralMinutes, 240)
        XCTAssertEqual(reloaded.rearmIdleMinutes, 1)
    }
}
