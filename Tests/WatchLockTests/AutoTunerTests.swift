import XCTest
@testable import WatchLock

/// 误锁反馈与自动调参（M3）。
final class AutoTunerTests: XCTestCase {
    private let defaults = AutoTuner.Thresholds(farRSSI: -70, farDwell: 5)

    func testFalseLockRate() {
        XCTAssertEqual(AutoTuner.falseLockRate(.init()), 0)
        XCTAssertEqual(AutoTuner.falseLockRate(.init(autoLocks: 10, falseLocks: 2)), 0.2, accuracy: .ulpOfOne)
        XCTAssertEqual(AutoTuner.falseLockRate(.init(autoLocks: 10, falseLocks: 20)), 1)
    }

    func testShouldRelax() {
        XCTAssertTrue(AutoTuner.shouldRelax(.init(autoLocks: 3, falseLocks: 1)))
        XCTAssertFalse(AutoTuner.shouldRelax(.init(autoLocks: 2, falseLocks: 1)), "样本不足不应调整")
        XCTAssertFalse(AutoTuner.shouldRelax(.init(autoLocks: 10, falseLocks: 2)), "误锁率等于容忍值不调整")
    }

    func testRelaxPrefersDistance() {
        let relaxed = AutoTuner.relax(.init(farRSSI: -70, farDwell: 5))
        XCTAssertEqual(relaxed.farRSSI, -72)
        XCTAssertEqual(relaxed.farDwell, 5)
    }

    func testRelaxFallsBackToDwell() {
        let relaxed = AutoTuner.relax(.init(farRSSI: -95, farDwell: 5))
        XCTAssertEqual(relaxed.farRSSI, -95)
        XCTAssertEqual(relaxed.farDwell, 7)
    }

    func testRelaxIsClamped() {
        let relaxed = AutoTuner.relax(.init(farRSSI: -95, farDwell: 30))
        XCTAssertEqual(relaxed.farDwell, 30)
    }

    func testTightenShortensDwellFirst() {
        let tightened = AutoTuner.tighten(.init(farRSSI: -72, farDwell: 8), defaults: defaults, nearRSSI: -55)
        XCTAssertEqual(tightened.farDwell, 7)
        XCTAssertEqual(tightened.farRSSI, -72)
    }

    func testTightenRaisesThresholdTowardDefault() {
        let tightened = AutoTuner.tighten(.init(farRSSI: -72, farDwell: 5), defaults: defaults, nearRSSI: -55)
        XCTAssertEqual(tightened.farRSSI, -71)
    }

    func testTightenNeverExceedsDefault() {
        // 当前 -64 比默认 -70 更激进，收紧方向应是回到默认，而不是继续变激进。
        let tightened = AutoTuner.tighten(.init(farRSSI: -64, farDwell: 5), defaults: defaults, nearRSSI: -58)
        XCTAssertEqual(tightened.farRSSI, -65)
    }

    func testTightenRespectsNearThreshold() {
        // 「在身边」-72 时，目标阈值被限制在 -77，避免两个阈值贴太近。
        let first = AutoTuner.tighten(.init(farRSSI: -78, farDwell: 5), defaults: defaults, nearRSSI: -72)
        XCTAssertEqual(first.farRSSI, -77)
        // 到达目标后再次收紧应保持不变，不能在两个值之间来回跳。
        let second = AutoTuner.tighten(first, defaults: defaults, nearRSSI: -72)
        XCTAssertEqual(second.farRSSI, -77)
    }

    func testSuggestRelaxesWhenFalseLockRateIsHigh() {
        let suggestion = AutoTuner.suggest(
            current: .init(farRSSI: -70, farDwell: 5),
            feedback: .init(autoLocks: 5, falseLocks: 2),
            defaults: defaults,
            nearRSSI: -55
        )
        XCTAssertEqual(suggestion, .init(farRSSI: -72, farDwell: 5))
    }

    func testSuggestTightensAfterLongCleanRun() {
        let suggestion = AutoTuner.suggest(
            current: .init(farRSSI: -75, farDwell: 5),
            feedback: .init(autoLocks: 20, falseLocks: 0),
            defaults: defaults,
            nearRSSI: -55
        )
        XCTAssertEqual(suggestion?.farRSSI, -74)
    }

    func testSuggestDoesNothingWhenAlreadyDefault() {
        XCTAssertNil(AutoTuner.suggest(
            current: defaults,
            feedback: .init(autoLocks: 50, falseLocks: 0),
            defaults: defaults,
            nearRSSI: -55
        ))
    }

    func testSuggestDoesNothingWithTooFewSamples() {
        XCTAssertNil(AutoTuner.suggest(
            current: .init(farRSSI: -70, farDwell: 5),
            feedback: .init(autoLocks: 1, falseLocks: 1),
            defaults: defaults,
            nearRSSI: -55
        ))
    }

    func testSettingsRecordFalseLockAppliesSuggestion() {
        let suiteName = "watchlock.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        store.farRSSI = -70
        store.farDwell = 5
        for _ in 0 ..< 3 { store.recordAutoLock() }

        let suggestion = store.recordFalseLock()
        XCTAssertEqual(suggestion?.farRSSI, -72)
        if let suggestion {
            store.applyTuned(suggestion)
        }
        XCTAssertEqual(store.farRSSI, -72)
        XCTAssertEqual(store.falseLockCount, 1)
        XCTAssertEqual(store.tuningFeedback.autoLocks, 3)

        store.resetTuningStats()
        XCTAssertEqual(store.tuningFeedback, .init(autoLocks: 0, falseLocks: 0))
    }
}
