import XCTest
@testable import WatchLock

/// ProximityEngine 单元测试（对应需求 §14.1 表格）。
final class ProximityEngineTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEngine() -> (ProximityEngine, EventRecorder) {
        var config = ProximityEngine.Config()
        config.nearRSSI = -55
        config.farRSSI = -70
        config.smoothing = 0.25
        config.farDwell = 5
        config.nearDwell = 1
        config.signalLostTimeout = 12
        config.measuredPower = -55
        config.pathLossExponent = 2.5
        let engine = ProximityEngine(config: config)
        let recorder = EventRecorder()
        engine.onEvent = { recorder.record($0) }
        return (engine, recorder)
    }

    /// RSSI 平滑：输出始终落在输入极值之间，不出现跳变。
    func testSmoothingStaysInsideInputRange() {
        let (engine, _) = makeEngine()
        for (offset, rssi) in [-70, -50, -70, -50].enumerated() {
            engine.update(rssi: rssi, at: base.addingTimeInterval(Double(offset)))
        }
        guard let sample = engine.lastSample else { return XCTFail("没有产生样本") }
        XCTAssertGreaterThan(sample.smoothedRSSI, -70)
        XCTAssertLessThan(sample.smoothedRSSI, -50)
    }

    /// 离开迟滞：RSSI 在死区内（-68 / -72）来回抖动，不应触发任何状态切换。
    func testHysteresisDeadZoneDoesNotCommit() {
        let (engine, recorder) = makeEngine()
        for index in 0 ..< 120 {
            let rssi = index % 2 == 0 ? -72 : -68
            engine.update(rssi: rssi, at: base.addingTimeInterval(Double(index) * 0.5))
        }
        XCTAssertEqual(recorder.events.count, 0, "死区内抖动不应产生任何事件")
        XCTAssertEqual(engine.status, .unknown)
    }

    /// 离开迟滞：临界值（-69 / -71）抖动 1 分钟，最多只锁定一次，且不会来回解锁/锁定。
    func testNoFlappingAtBoundary() {
        let (engine, recorder) = makeEngine()
        for index in 0 ..< 120 {
            let rssi = index % 2 == 0 ? -71 : -69
            engine.update(rssi: rssi, at: base.addingTimeInterval(Double(index) * 0.5))
        }
        XCTAssertLessThanOrEqual(recorder.farCount, 1)
        XCTAssertEqual(recorder.nearCount, 0)
        if recorder.farCount == 1 {
            XCTAssertEqual(recorder.lastFarReason, .beyondThreshold)
        }
    }

    /// 离开锁定：持续 -75 dBm 超过 5 秒，只触发一次 becameFar。
    func testSustainedFarTriggersLockOnce() {
        let (engine, recorder) = makeEngine()
        for offset in 0 ..< 20 {
            engine.update(rssi: -75, at: base.addingTimeInterval(Double(offset)))
        }
        XCTAssertEqual(recorder.farCount, 1)
        XCTAssertEqual(recorder.lastFarReason, .beyondThreshold)
        XCTAssertEqual(engine.status, .far)
    }

    /// 未达到宽限时间（4 秒）不锁定。
    func testFarDwellNotReached() {
        let (engine, recorder) = makeEngine()
        for offset in 0 ..< 5 {
            engine.update(rssi: -75, at: base.addingTimeInterval(Double(offset)))
        }
        XCTAssertEqual(recorder.farCount, 0)
        XCTAssertEqual(engine.status, .unknown)
    }

    /// 信号丢失：12 秒无样本触发一次 becameFar，且原因与「超出距离」可区分。
    func testSignalLostTriggersFarWithReason() {
        let (engine, recorder) = makeEngine()
        engine.update(rssi: -50, at: base)
        engine.tick(now: base.addingTimeInterval(1))
        engine.tick(now: base.addingTimeInterval(2))
        XCTAssertEqual(recorder.nearCount, 1)

        // 丢失前信号很强（-50），超时被放宽到 30 秒
        engine.tick(now: base.addingTimeInterval(20))
        XCTAssertEqual(recorder.farCount, 0, "未超过放宽后的 signalLostTimeout 不应判定离开")

        engine.tick(now: base.addingTimeInterval(31))
        XCTAssertEqual(recorder.farCount, 1)
        XCTAssertEqual(recorder.lastFarReason, .signalLost)
        XCTAssertEqual(engine.status, .far)
    }

    /// 靠近恢复：持续 -50 dBm 超过 1 秒触发一次 becameNear。
    func testNearDwellTriggersUnlock() {
        let (engine, recorder) = makeEngine()
        for offset in 0 ..< 3 {
            engine.update(rssi: -50, at: base.addingTimeInterval(Double(offset)))
        }
        XCTAssertEqual(recorder.nearCount, 1)
        XCTAssertEqual(engine.status, .near)
    }

    /// 远离后再靠近，能够恢复到 near。
    func testFarThenNearRecovery() {
        let (engine, recorder) = makeEngine()
        for offset in 0 ..< 10 {
            engine.update(rssi: -80, at: base.addingTimeInterval(Double(offset)))
        }
        XCTAssertEqual(recorder.farCount, 1)

        // EWMA（α=0.25）需要数个样本才能从 -80 收敛到近阈值以上，给足 10 秒。
        for offset in 10 ..< 20 {
            engine.update(rssi: -45, at: base.addingTimeInterval(Double(offset)))
        }
        XCTAssertEqual(recorder.nearCount, 1)
        XCTAssertEqual(engine.status, .near)
    }

    /// 距离估算：标定值处约 1 米，信号越弱距离越远。
    func testDistanceEstimation() {
        let (engine, _) = makeEngine()
        XCTAssertEqual(engine.estimateDistance(rssi: -55), 1.0, accuracy: 0.001)
        XCTAssertEqual(engine.estimateDistance(rssi: -65), pow(10, 10.0 / 25.0), accuracy: 0.001)
        XCTAssertGreaterThan(engine.estimateDistance(rssi: -75), engine.estimateDistance(rssi: -55))
    }

    /// reset 会清空状态，用于睡眠唤醒后重建判定。
    func testResetClearsState() {
        let (engine, recorder) = makeEngine()
        for offset in 0 ..< 10 {
            engine.update(rssi: -80, at: base.addingTimeInterval(Double(offset)))
        }
        XCTAssertEqual(recorder.farCount, 1)

        engine.reset()
        XCTAssertEqual(engine.status, .unknown)
        XCTAssertNil(engine.lastSample)

        for offset in 0 ..< 3 {
            engine.update(rssi: -50, at: base.addingTimeInterval(Double(20 + offset)))
        }
        XCTAssertEqual(recorder.nearCount, 1)
    }

    // MARK: - 信号丢失保护（手表在旁边但广播被系统节流时不该锁屏）

    func testEffectiveSignalLostTimeout() {
        let (engine, _) = makeEngine()
        engine.config.smoothing = 1.0
        engine.update(rssi: -50, at: base)
        XCTAssertEqual(engine.effectiveSignalLostTimeout, 30, accuracy: .ulpOfOne)
        engine.update(rssi: -60, at: base.addingTimeInterval(1))
        XCTAssertEqual(engine.effectiveSignalLostTimeout, 12, accuracy: .ulpOfOne)
    }

    func testSignalLossIsRelaxedWhenRecentlyNear() {
        let (engine, recorder) = makeEngine()
        engine.update(rssi: -50, at: base)
        engine.tick(now: base.addingTimeInterval(2))
        engine.tick(now: base.addingTimeInterval(3))
        XCTAssertEqual(recorder.nearCount, 1)

        // 丢失前信号很强：超时放宽到 12 × 2.5 = 30 秒
        engine.tick(now: base.addingTimeInterval(20))
        XCTAssertEqual(recorder.farCount, 0)
        engine.tick(now: base.addingTimeInterval(31))
        XCTAssertEqual(recorder.farCount, 1)
        XCTAssertEqual(recorder.lastFarReason, .signalLost)
    }

    func testSignalLossUsesNormalTimeoutWhenAlreadyWeak() {
        let (engine, recorder) = makeEngine()
        // -60 落在死区：不会触发阈值锁定，也不算「最近很近」
        engine.update(rssi: -60, at: base)
        engine.tick(now: base.addingTimeInterval(11))
        XCTAssertEqual(recorder.events.count, 0)
        engine.tick(now: base.addingTimeInterval(13))
        XCTAssertEqual(recorder.farCount, 1)
        XCTAssertEqual(recorder.lastFarReason, .signalLost)
    }

    func testPresenceWithoutValidRSSIDoesNotLock() {
        // 广播还在、只是系统没给信号强度时，按「在场」处理（实测误锁的真实路径之一）。
        let (engine, recorder) = makeEngine()
        engine.config.signalLostTimeout = 5
        engine.update(rssi: -60, at: base)
        engine.notePresence(at: base.addingTimeInterval(4))
        engine.tick(now: base.addingTimeInterval(6))
        XCTAssertEqual(recorder.farCount, 0)
    }

    func testSignalLossStillLocksWithoutAnyPresence() {
        let (engine, recorder) = makeEngine()
        engine.config.signalLostTimeout = 5
        engine.update(rssi: -60, at: base)
        engine.tick(now: base.addingTimeInterval(6))
        XCTAssertEqual(recorder.farCount, 1)
    }

    func testSignalLossDoesNotLockWhenDisabled() {
        let (engine, recorder) = makeEngine()
        engine.config.lockOnSignalLoss = false
        engine.update(rssi: -60, at: base)
        engine.tick(now: base.addingTimeInterval(40))
        XCTAssertEqual(recorder.farCount, 0)
        XCTAssertEqual(engine.status, .unknown)
    }
}

/// 记录状态机事件，便于断言次数与原因。
private final class EventRecorder {
    private(set) var events: [ProximityEngine.Event] = []

    func record(_ event: ProximityEngine.Event) {
        events.append(event)
    }

    var farCount: Int {
        events.reduce(0) { count, event in
            if case .becameFar = event { return count + 1 }
            return count
        }
    }

    var nearCount: Int {
        events.reduce(0) { count, event in
            if case .becameNear = event { return count + 1 }
            return count
        }
    }

    var lastFarReason: ProximityEngine.FarReason? {
        for event in events.reversed() {
            if case .becameFar(let reason) = event { return reason }
        }
        return nil
    }
}
