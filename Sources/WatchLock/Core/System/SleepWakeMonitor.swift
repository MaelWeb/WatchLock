import AppKit
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
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

    init(
        workspace: NotificationCenter = NSWorkspace.shared.notificationCenter,
        distributed: NotificationCenter = DistributedNotificationCenter.default()
    ) {
        self.workspace = workspace
        self.distributed = distributed
    }

    func start() {
        guard workspaceObservers.isEmpty, distributedObservers.isEmpty else { return }
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
            self?.onWake?()
        })
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isDisplayAsleep = true
            DiagnosticsLog.shared.append(.info, "显示器已熄屏")
            self?.onDisplaySleep?()
        })
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Apple NSWorkspace 文档：此通知只表示屏幕唤醒，不表示会话已解锁。
            self?.isDisplayAsleep = false
            DiagnosticsLog.shared.append(.info, "收到系统显示器唤醒通知（不代表会话解锁）")
            self?.onDisplayWake?()
        })

        // 延用既有非公开会话锁定通知；系统升级后的通知行为仍需实机验证。
        distributedObservers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isScreenLocked = true
            DiagnosticsLog.shared.append(.info, "收到会话锁定通知")
            self?.onScreenLocked?()
        })
        distributedObservers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isScreenLocked = false
            DiagnosticsLog.shared.append(.info, "收到会话解锁通知")
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
