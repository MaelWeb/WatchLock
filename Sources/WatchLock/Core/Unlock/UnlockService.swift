import AppKit
import Foundation

/// 靠近事件的处理服务。
final class UnlockService {
    private let settings: SettingsStore
    private let keychain: KeychainStore
    private let wakeDisplay: () -> Bool
    private let isScreenLocked: () -> Bool
    private let evaluatePrerequisites: () -> [String]

    /// 两次靠近处理之间的最小间隔，避免临界抖动时反复唤醒（FR-05 / FR-12）。
    var approachCooldown: TimeInterval = 10
    private var lastApproachAt: Date?
    private var pendingApproachRetry = false

    init(
        settings: SettingsStore,
        keychain: KeychainStore = .init(),
        wakeDisplay: @escaping () -> Bool = { ScreenLocker.wakeDisplay() },
        isScreenLocked: @escaping () -> Bool = { false },
        evaluatePrerequisites: @escaping () -> [String] = { AutoUnlockPrerequisites.evaluate() }
    ) {
        self.settings = settings
        self.keychain = keychain
        self.wakeDisplay = wakeDisplay
        self.isScreenLocked = isScreenLocked
        self.evaluatePrerequisites = evaluatePrerequisites
    }

    /// 手表靠近时的处理入口，锁屏状态不影响点亮显示器。
    func handleApproach(now: Date = Date()) {
        pendingApproachRetry = false
        guard canHandleApproach else { return }
        guard cooldownElapsed(at: now) else {
            pendingApproachRetry = true
            DiagnosticsLog.shared.append(.info, "靠近事件处于冷却期，等待新的近距离样本后重试一次")
            return
        }
        pendingApproachRetry = !requestWake(now: now)
    }

    /// 仅由新的有效近距离样本驱动；每次靠近事件最多补偿一次，失联时不唤醒。
    func retryPendingApproach(now: Date = Date()) {
        guard pendingApproachRetry else { return }
        guard canHandleApproach else {
            cancelPendingApproach()
            return
        }
        guard cooldownElapsed(at: now) else { return }
        pendingApproachRetry = false
        DiagnosticsLog.shared.append(.info, "手表仍在近距离，重试显示器唤醒请求")
        _ = requestWake(now: now)
    }

    func cancelPendingApproach() {
        pendingApproachRetry = false
    }

    private var canHandleApproach: Bool {
        settings.isEnabled && !settings.isPaused && settings.wakeDisplayOnApproach
    }

    private func cooldownElapsed(at now: Date) -> Bool {
        guard let last = lastApproachAt else { return true }
        return now.timeIntervalSince(last) >= approachCooldown
    }

    private func requestWake(now: Date) -> Bool {
        lastApproachAt = now
        guard wakeDisplay() else { return false }

        switch settings.unlockStrategy {
        case .wakeOnly:
            break
        case .systemAutoUnlock:
            if isScreenLocked() { verifyAutoUnlockPrerequisites() }
        case .managedPassword:
            typeLoginPassword()
        }
        return true
    }

    /// 检查系统「使用 Apple Watch 解锁」的前置条件，缺失则提示。
    func verifyAutoUnlockPrerequisites() {
        let missing = evaluatePrerequisites()
        guard !missing.isEmpty else { return }
        DiagnosticsLog.shared.append(.warning, "自动解锁前置条件缺失：\(missing.joined(separator: "；"))")
        if settings.notificationsEnabled {
            NotificationPresenter.shared.notify(
                title: "无法自动解锁",
                body: missing.joined(separator: "；"),
                reason: .autoUnlockMissing
            )
        }
    }

    /// 从钥匙串读取密码并模拟键入。
    func typeLoginPassword() {
        guard settings.unlockStrategy == .managedPassword, isScreenLocked() else { return }
        do {
            guard let password = try keychain.loadPassword(), !password.isEmpty else {
                DiagnosticsLog.shared.append(.error, "钥匙串中没有可用的登录密码")
                return
            }
            guard AccessibilityProbe.isTrusted(prompt: true) else {
                DiagnosticsLog.shared.append(.error, "缺少辅助功能权限，无法模拟键入密码")
                return
            }
            let script = """
            tell application "System Events"
                keystroke \(AppleScript.quote(password))
                delay 0.2
                keystroke return
            end tell
            """
            let process = Process()
            process.launchPath = "/usr/bin/osascript"
            process.arguments = ["-e", script]
            try process.run()
            DiagnosticsLog.shared.append(.info, "已触发托管密码输入")
        } catch {
            DiagnosticsLog.shared.append(.error, "托管密码输入失败：\(error.localizedDescription)")
        }
    }

}

/// AppleScript 字符串转义。
enum AppleScript {
    static func quote(_ string: String) -> String {
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

/// 轻量 shell 调用。
enum Shell {
    @discardableResult
    static func run(_ launchPath: String, arguments: [String] = []) -> String {
        let process = Process()
        process.launchPath = launchPath
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// 辅助功能权限探测。
enum AccessibilityProbe {
    private static let promptLock = NSLock()
    private static var didPrompt = false

    static func isTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 检查权限；未授权时**本次启动内只弹一次**系统授权框。
    ///
    /// 自动锁定可能在手表临界点反复触发，每次都弹框会刷屏；弹一次足以把应用加进
    /// 「辅助功能」列表，之后由通知和诊断日志提示用户去勾选。
    static func ensureTrusted() -> Bool {
        if isTrusted(prompt: false) { return true }
        promptLock.lock()
        defer { promptLock.unlock() }
        let shouldPrompt = !didPrompt
        didPrompt = true
        return shouldPrompt ? isTrusted(prompt: true) : false
    }
}
