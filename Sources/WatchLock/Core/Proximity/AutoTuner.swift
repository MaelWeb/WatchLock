import Foundation

/// 误锁反馈与自动调参（M3）。
///
/// 思路（保守优先）：
/// 1. 每次自动锁定记一次样本；用户在菜单栏点「刚才误锁了」记一次误锁；
/// 2. 误锁率超过容忍值且样本足够时，放宽判定（优先放宽距离，其次放宽时间）；
/// 3. 长时间无误锁时，缓慢向默认值收紧，避免参数永久漂移。
///
/// 纯函数、无副作用，便于单元测试。
enum AutoTuner {
    /// 参与调参的阈值（只调整「已离开」侧，避免影响靠近唤醒体验）。
    struct Thresholds: Equatable {
        var farRSSI: Int
        var farDwell: Double
    }

    /// 反馈统计。
    struct Feedback: Equatable {
        var autoLocks: Int = 0
        var falseLocks: Int = 0
    }

    /// 可调范围与步长。
    enum Limits {
        static let minFarRSSI = -95
        static let maxFarRSSI = -50
        static let minFarDwell: Double = 0
        static let maxFarDwell: Double = 30
        static let rssiStep = 2
        static let dwellStep: Double = 2
    }

    /// 误锁率（0...1）；没有样本时为 0。
    static func falseLockRate(_ feedback: Feedback) -> Double {
        guard feedback.autoLocks > 0 else { return 0 }
        return min(1, Double(feedback.falseLocks) / Double(feedback.autoLocks))
    }

    /// 是否需要放宽：样本数达到下限且误锁率超过容忍值。
    static func shouldRelax(
        _ feedback: Feedback,
        minimumSamples: Int = 3,
        tolerance: Double = 0.2
    ) -> Bool {
        feedback.autoLocks >= minimumSamples && falseLockRate(feedback) > tolerance
    }

    /// 放宽一步：先把「已离开」阈值下调（需要更远才锁定），到下限后再延长等待时间。
    static func relax(_ current: Thresholds) -> Thresholds {
        var next = current
        if next.farRSSI - Limits.rssiStep >= Limits.minFarRSSI {
            next.farRSSI = max(Limits.minFarRSSI, next.farRSSI - Limits.rssiStep)
        } else {
            next.farDwell = min(Limits.maxFarDwell, next.farDwell + Limits.dwellStep)
        }
        return next
    }

    /// 收紧一步：先缩短等待时间，再向目标阈值移动 1 dBm。
    ///
    /// 目标阈值取「默认值」与「在身边阈值 - 5 dBm」中较小的一个，
    /// 保证收紧后不会比默认行为更激进，也不会和「在身边」阈值贴太近。
    static func tighten(_ current: Thresholds, defaults: Thresholds, nearRSSI: Int) -> Thresholds {
        var next = current
        if next.farDwell > defaults.farDwell {
            next.farDwell = max(defaults.farDwell, next.farDwell - Limits.dwellStep / 2)
            return next
        }
        let target = min(defaults.farRSSI, nearRSSI - 5)
        if next.farRSSI > target {
            next.farRSSI = max(Limits.minFarRSSI, next.farRSSI - 1)
        } else if next.farRSSI < target {
            next.farRSSI = min(Limits.maxFarRSSI, next.farRSSI + 1)
        }
        return next
    }

    /// 是否需要收紧：连续 `window` 次自动锁定中没有误锁。
    static func shouldTighten(
        _ feedback: Feedback,
        current: Thresholds,
        defaults: Thresholds,
        window: Int = 20
    ) -> Bool {
        guard feedback.falseLocks == 0, feedback.autoLocks >= window else { return false }
        return current != defaults
    }

    /// 依据反馈给出调整建议；无需调整时返回 nil。
    static func suggest(
        current: Thresholds,
        feedback: Feedback,
        defaults: Thresholds,
        nearRSSI: Int,
        tolerance: Double = 0.2,
        window: Int = 20
    ) -> Thresholds? {
        if shouldRelax(feedback, tolerance: tolerance) {
            return relax(current)
        }
        if shouldTighten(feedback, current: current, defaults: defaults, window: window) {
            return tighten(current, defaults: defaults, nearRSSI: nearRSSI)
        }
        return nil
    }
}
