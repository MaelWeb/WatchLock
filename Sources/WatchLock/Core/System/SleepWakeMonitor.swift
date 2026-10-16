import AppKit
import Foundation

/// 监听睡眠 / 唤醒 / 锁屏 / 解锁事件，用于在唤醒后给出宽限期，避免误锁。
final class SleepWakeMonitor {
    var onWake: (() -> Void)?
    var onSleep: (() -> Void)?
    var onScreenLocked: (() -> Void)?
    var onScreenUnlocked: (() -> Void)?

    private(set) var isScreenLocked = false
    private var observers: [NSObjectProtocol] = []

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onSleep?()
        })
        observers.append(workspace.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onWake?()
        })
        observers.append(workspace.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isScreenLocked = true
            self?.onScreenLocked?()
        })
        observers.append(workspace.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isScreenLocked = false
            self?.onScreenUnlocked?()
        })

        let distributed = DistributedNotificationCenter.default
        observers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isScreenLocked = true
            self?.onScreenLocked?()
        })
        observers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isScreenLocked = false
            self?.onScreenUnlocked?()
        })
    }

    func stop() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default
        for observer in observers {
            workspace.removeObserver(observer)
            distributed.removeObserver(observer)
        }
        observers.removeAll()
    }
}
