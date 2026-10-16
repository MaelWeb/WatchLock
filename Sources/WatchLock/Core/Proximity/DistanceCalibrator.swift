import Foundation

/// 距离模型校准（FR-14）。
///
/// 把「在指定位置采样到的 RSSI 序列」换算成可写入设置的参数：
/// 1. 1 米处采样 → 写入 `measuredPower`；
/// 2. 「在身边」「已离开」两点采样 → 生成 `nearRSSI` / `farRSSI` 双阈值。
///
/// 纯函数、无副作用，便于单元测试。
enum DistanceCalibrator {
    /// 阈值生成结果。
    struct Thresholds: Equatable {
        let nearRSSI: Int
        let farRSSI: Int
    }

    /// 绑定后自动校准的结果（含 1 米标定值）。
    struct AutoResult: Equatable {
        let nearRSSI: Int
        let farRSSI: Int
        let measuredPower: Int
    }

    /// 绑定时的自动校准：绑定那一刻手表就在手边，可直接把观测到的信号作为「在身边」基准。
    ///
    /// - 在身边阈值 = 中位数 - 5 dBm（留一点余量，避免正常姿势变化就掉出区间）；
    /// - 已离开阈值 = 中位数 - 22 dBm（需要明显走远才锁定）；
    /// - 两者至少相差 10 dBm。样本不足（默认少于 5 个）时回退到原值。
    static func autoThresholds(
        from samples: [Int],
        fallback: AutoResult,
        nearMargin: Int = 5,
        farMargin: Int = 22,
        minimumSamples: Int = 5
    ) -> AutoResult {
        guard samples.count >= minimumSamples, let median = median(samples) else { return fallback }

        let near = clamp(median - nearMargin, -90 ... -35)
        var far = clamp(median - farMargin, -100 ... -50)
        if near - far < 10 {
            far = clamp(near - 10, -100 ... -50)
        }
        return AutoResult(nearRSSI: near, farRSSI: far, measuredPower: clamp(median, -90 ... -30))
    }

    /// 采样序列的中位数（偶数取中间两数均值），用于抑制偶发的离群样本。
    static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 1 { return sorted[middle] }
        return Int((Double(sorted[middle - 1]) + Double(sorted[middle])) / 2.0)
    }

    /// 1 米标定值；样本不足时回退到原值。
    static func measuredPower(
        samples: [Int],
        fallback: Int,
        range: ClosedRange<Int> = -90 ... -30
    ) -> Int {
        guard let value = median(samples) else { return fallback }
        return clamp(value, range)
    }

    /// 由「在身边」「已离开」两点采样生成双阈值。
    ///
    /// - 在身边阈值 = 采样中位数 - margin：保证回到该位置时能被判定为 near；
    /// - 已离开阈值 = 采样中位数 + margin：保证走到该位置时能被判定为 far；
    /// - 两者差值不足 `minimumGap` 时优先下压已离开阈值，降低误锁概率。
    static func thresholds(
        nearSamples: [Int],
        farSamples: [Int],
        fallback: Thresholds,
        margin: Int = 3,
        minimumGap: Int = 8
    ) -> Thresholds {
        guard let near = median(nearSamples), let far = median(farSamples) else { return fallback }

        var nearThreshold = clamp(near - margin, -90 ... -35)
        var farThreshold = clamp(far + margin, -100 ... -50)

        if nearThreshold - farThreshold < minimumGap {
            farThreshold = clamp(nearThreshold - minimumGap, -100 ... -50)
            if nearThreshold - farThreshold < minimumGap {
                nearThreshold = clamp(farThreshold + minimumGap, -90 ... -35)
            }
        }
        return Thresholds(nearRSSI: nearThreshold, farRSSI: farThreshold)
    }

    private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
