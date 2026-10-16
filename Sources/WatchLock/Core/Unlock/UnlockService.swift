import AppKit
import Foundation

/// 靠近事件的处理服务。
final class UnlockService {
    private let settings: SettingsStore
    private let keychain: KeychainStore

    /// 两次靠近处理之间的最小间隔，避免临界抖动时反复唤醒（FR-05 / FR-12）。
    var approachCooldown: TimeInterval = 10
    private var lastApproachAt: Date?

    init(settings: SettingsStore, keychain: KeychainStore = .init()) {
        self.settings = settings
        self.keychain = keychain
    }

    /// 手表靠近时的处理入口。
    func handleApproach(now: Date = Date()) {
        guard settings.wakeDisplayOnApproach else { return }

        if let last = lastApproachAt, now.timeIntervalSince(last) < approachCooldown {
            DiagnosticsLog.shared.append(.info, "靠近事件过于频繁，跳过本次唤醒")
            return
        }
        lastApproachAt = now

        guard ScreenLocker.wakeDisplay(seconds: 1) else { return }

        switch settings.unlockStrategy {
        case .wakeOnly:
            break
        case .systemAutoUnlock:
            verifyAutoUnlockPrerequisites()
        case .managedPassword:
            typeLoginPassword()
        }
    }

    /// 检查系统「使用 Apple Watch 解锁」的前置条件，缺失则提示。
    func verifyAutoUnlockPrerequisites() {
        var missing: [String] = []
        if !isScreenSaverPasswordRequired {
            missing.append("「系统设置 → 锁定屏幕」中未要求立即输入密码")
        }
        if !isAppleWatchPairedHeuristic {
            missing.append("未检测到与本 Mac 同一 iCloud 账户的 Apple Watch（无法自动确认）")
        }
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
        guard settings.unlockStrategy == .managedPassword else { return }
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

    // MARK: - 前置条件探测

    /// 读取 `screensaver` 偏好判断是否要求立即输入密码。
    private var isScreenSaverPasswordRequired: Bool {
        guard let value = UserDefaults(suiteName: "com.apple.screensaver")?.object(forKey: "askForPassword") as? Int else {
            return false
        }
        return value == 1
    }

    /// 仅能判断本机是否有已配对的蓝牙设备，无法直接确认 iPhone/手表配对关系。
    ///
    /// `system_profiler` 开销较大，结果在进程内缓存（FR-12 低耗电）。
    private var isAppleWatchPairedHeuristic: Bool {
        if let cached = cachedPairedWatch { return cached }
        let output = Shell.run("/usr/sbin/system_profiler", arguments: ["SPBluetoothDataType"])
        let result = output.localizedCaseInsensitiveContains("Apple Watch")
        cachedPairedWatch = result
        return result
    }

    private var cachedPairedWatch: Bool?
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
