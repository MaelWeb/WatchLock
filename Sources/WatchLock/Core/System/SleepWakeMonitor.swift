import AppKit
import CoreGraphics
import Foundation

/// 监听睡眠 / 唤醒 / 锁屏 / 解锁事件，用于在唤醒后给出宽限期，避免误锁。
final class SleepWakeMonitor {
    var onWake: (() -> Void)?
    var onSleep: (() -> Void)?
    var onScreenLocked: (() -> Void)?
    var onScreenUnlocked: (() -> Void)?
    var onDisplaySleep: (() -> Void)?
    var onDisplayWake: (() -> Void)?

    private(set) var isScreenLocked = false
    private(set) var isDisplayAsleep = false
    private(set) var isSystemSleeping = false
    private let workspace: NotificationCenter
    private let distributed: NotificationCenter
    /// 直接向系统查询会话是否锁定；`nil` 表示查询不到（保持现有状态）。测试里可注入。
    private let sessionLockProbe: () -> Bool?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

    init(
        workspace: NotificationCenter = NSWorkspace.shared.notificationCenter,
        distributed: NotificationCenter = DistributedNotificationCenter.default(),
        sessionLockProbe: @escaping () -> Bool? = { SessionLockProbe.isLocked() }
    ) {
        self.workspace = workspace
        self.distributed = distributed
        self.sessionLockProbe = sessionLockProbe
    }

    /// 用系统查询校正会话锁定状态，并返回校正后的结果。
    ///
    /// 会话锁定/解锁只靠非公开分布式通知更新，漏掉一次「解锁」（例如睡眠期间）会让
    /// `isScreenLocked` 永久为 true，进而一直跳过自动锁定。因此在启动、唤醒、
    /// 以及每次需要依赖该状态的动作之前，都向系统重新确认一次。
    @discardableResult
    func refreshSessionLockState() -> Bool {
        guard let actual = sessionLockProbe(), actual != isScreenLocked else { return isScreenLocked }
        isScreenLocked = actual
        DiagnosticsLog.shared.append(.warning, String(localized: "会话锁定状态与通知记录不一致，已按系统查询校正为\(actual ? String(localized: "已锁定") : String(localized: "未锁定"))"))
        if actual { onScreenLocked?() } else { onScreenUnlocked?() }
        return actual
    }

    func start() {
        guard workspaceObservers.isEmpty, distributedObservers.isEmpty else { return }
        refreshSessionLockState()
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isSystemSleeping = true
            self?.onSleep?()
        })
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isSystemSleeping = false
            self?.refreshSessionLockState()
            self?.onWake?()
        })
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isDisplayAsleep = true
            DiagnosticsLog.shared.append(.info, String(localized: "显示器已熄屏"))
            self?.onDisplaySleep?()
        })
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Apple NSWorkspace 文档：此通知只表示屏幕唤醒，不表示会话已解锁。
            self?.isDisplayAsleep = false
            DiagnosticsLog.shared.append(.info, String(localized: "收到系统显示器唤醒通知（不代表会话解锁）"))
            self?.onDisplayWake?()
        })

        // 延用既有非公开会话锁定通知；系统升级后的通知行为仍需实机验证。
        distributedObservers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isScreenLocked = true
            DiagnosticsLog.shared.append(.info, String(localized: "收到会话锁定通知"))
            self?.onScreenLocked?()
        })
        distributedObservers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isScreenLocked = false
            DiagnosticsLog.shared.append(.info, String(localized: "收到会话解锁通知"))
            self?.onScreenUnlocked?()
        })
    }

    func stop() {
        for observer in workspaceObservers { workspace.removeObserver(observer) }
        for observer in distributedObservers { distributed.removeObserver(observer) }
        workspaceObservers.removeAll()
        distributedObservers.removeAll()
    }

    deinit {
        stop()
    }
}

/// 向窗口服务器查询当前会话是否锁定。
///
/// 依据：`CGSessionCopyCurrentDictionary` 是公开 API（Apple 文档：返回调用者所在窗口服务器会话的字典，
/// 不在 GUI 会话中时为 NULL）；但「锁屏」对应的 `CGSSessionScreenIsLocked` 键**未文档化**，
/// 只在社区做法里出现（锁屏时存在，未锁屏时不存在）。macOS 26.6.1 解锁状态下实测该键不存在，
/// 与社区一致；**锁屏状态下的取值待真机验证**。因此查询失败时返回 `nil`，不改变现有状态。
enum SessionLockProbe {
    static let lockedKey = "CGSSessionScreenIsLocked"

    static func isLocked() -> Bool? {
        guard let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any] else { return nil }
        return isLocked(in: dictionary)
    }

    /// 纯函数，便于测试：键不存在视为未锁定；存在时按布尔/数值取值，无法解读则按已锁定处理（社区约定「存在即锁定」）。
    static func isLocked(in dictionary: [String: Any]) -> Bool {
        guard let value = dictionary[lockedKey] else { return false }
        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.boolValue }
        return true
    }
}
