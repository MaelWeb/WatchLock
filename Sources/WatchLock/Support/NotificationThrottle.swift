import Foundation

/// 通知频率限制器（FR-09）：同一原因在 `interval` 内最多发送一条。
///
/// 纯值类型、不依赖系统时间以外的任何环境，便于单元测试。
struct NotificationThrottle {
    /// 同一 key 的最小发送间隔，默认 5 分钟。
    var interval: TimeInterval
    private var lastSentAt: [String: Date]

    init(interval: TimeInterval = 300) {
        self.interval = interval
        self.lastSentAt = [:]
    }

    /// 判断是否允许发送；允许时会记录本次时间。
    mutating func shouldSend(key: String, now: Date = Date()) -> Bool {
        if let last = lastSentAt[key], now.timeIntervalSince(last) < interval {
            return false
        }
        lastSentAt[key] = now
        return true
    }

    /// 距离下一次可发送的剩余秒数（0 表示立即可发）。
    func remainingCooldown(key: String, now: Date = Date()) -> TimeInterval {
        guard let last = lastSentAt[key] else { return 0 }
        return max(0, interval - now.timeIntervalSince(last))
    }

    mutating func reset() {
        lastSentAt.removeAll()
    }
}
