import Foundation
import UserNotifications

/// 系统通知发送器（FR-09）。
///
/// 职责：
/// 1. 首次发送前请求通知授权；
/// 2. 按「原因」做频率限制，避免手表在临界点抖动时反复弹通知。
final class NotificationPresenter {
    static let shared = NotificationPresenter()

    /// 通知原因，同时作为频率限制的 key。
    enum Reason: String {
        case locked
        case lockBlocked
        case autoUnlockMissing
        case bluetoothIssue

        var key: String { rawValue }
    }

    private var throttle = NotificationThrottle()
    private var didRequestAuthorization = false
    private let center = UNUserNotificationCenter.current()

    private init() {}

    /// 在应用启动时调用；重复调用只请求一次。
    func requestAuthorizationIfNeeded() {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                DiagnosticsLog.shared.append(.error, String(localized: "通知授权失败：\(error.localizedDescription)"))
            } else if !granted {
                DiagnosticsLog.shared.append(.warning, String(localized: "用户未授权通知，锁定提醒将不会显示"))
            }
        }
    }

    /// 发送通知；`reason` 相同的通知在 5 分钟内最多一条。
    /// - Returns: 实际是否发出（被限流时返回 false）。
    @discardableResult
    func notify(title: String, body: String, reason: Reason, now: Date = Date()) -> Bool {
        guard throttle.shouldSend(key: reason.key, now: now) else {
            DiagnosticsLog.shared.append(.info, String(localized: "通知被限流，跳过：\(reason.key)"))
            return false
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request) { error in
            if let error {
                DiagnosticsLog.shared.append(.error, String(localized: "通知发送失败：\(error.localizedDescription)"))
            }
        }
        return true
    }

    /// 仅用于测试：重置限流状态。
    func resetThrottle() {
        throttle.reset()
    }
}
