import Foundation

/// 锁屏执行方式。
///
/// macOS 没有公开的「立即锁屏」API，以下均为工程上常用手段，
/// 优先级：`cgSessionSuspend`（等价于快速用户切换的锁屏）。
enum LockMethod: String, CaseIterable, Identifiable {
    case controlCommandQ
    case cgSessionSuspend
    case displaySleep
    case systemSleep
    case customCommand

    var id: String { rawValue }

    var title: String {
        switch self {
        case .controlCommandQ: return "锁定屏幕（⌃⌘Q，推荐）"
        case .cgSessionSuspend: return "锁定屏幕（CGSession，旧系统）"
        case .displaySleep: return "仅关闭显示器"
        case .systemSleep: return "进入睡眠"
        case .customCommand: return "自定义命令"
        }
    }

    var detail: String {
        switch self {
        case .controlCommandQ:
            return "用 AppleScript 模拟 ⌃⌘Q，效果与系统锁屏一致。首次使用需要在「系统设置 → 隐私与安全性 → 辅助功能」中授权。"
        case .cgSessionSuspend:
            return "调用 CGSession -suspend。该可执行文件在 macOS 26 上已被移除，仅适用于 macOS 14/15。"
        case .displaySleep:
            return "调用 pmset displaysleepnow，只熄灭屏幕，不锁定会话；若系统设为息屏后立即要求密码，效果等同锁屏。"
        case .systemSleep:
            return "调用 pmset sleepnow，整机进入睡眠。"
        case .customCommand:
            return "执行自定义 shell 命令，可用于对接脚本或企业管控工具。"
        }
    }

    /// 执行时是否需要「辅助功能」权限。
    ///
    /// ⌃⌘Q 是通过 System Events 模拟按键实现的，没有该权限会以 1002「不允许发送按键」失败。
    /// 自定义命令的内容不可知，不做预检，失败时靠输出里的错误码给提示。
    var requiresAccessibility: Bool {
        self == .controlCommandQ
    }

    var command: String? {
        switch self {
        case .controlCommandQ:
            return "/usr/bin/osascript -e 'tell application \"System Events\" to keystroke \"q\" using {command down, control down}'"
        case .cgSessionSuspend:
            return "\"/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession\" -suspend"
        case .displaySleep:
            return "/usr/bin/pmset displaysleepnow"
        case .systemSleep:
            return "/usr/bin/pmset sleepnow"
        case .customCommand:
            return nil
        }
    }
}

/// 执行锁屏动作。
struct ScreenLocker {
    var method: LockMethod
    var customCommand: String
    /// 辅助功能权限检查；默认走系统探测（未授权时本次启动只弹一次授权框），测试里可注入。
    var accessibilityCheck: () -> Bool = { AccessibilityProbe.ensureTrusted() }

    /// 缺权限时给用户的处理指引（诊断日志与通知共用）。
    static let accessibilityGuidance =
        "缺少辅助功能权限：⌃⌘Q 锁屏需要在「系统设置 → 隐私与安全性 → 辅助功能」中勾选 WatchLock。"
        + "若已勾选仍失败，多半是重新打包后签名变了、旧授权失效：选中列表里的 WatchLock 点「−」删除，再重新添加。"

    /// 通知里用的简短版本。
    static let accessibilityNotificationBody =
        "⌃⌘Q 锁屏需要辅助功能权限：系统设置 → 隐私与安全性 → 辅助功能 → 勾选 WatchLock"

    /// 执行前就能确定会失败的原因；`nil` 表示可以执行。
    func permissionIssue() -> String? {
        guard method.requiresAccessibility, !accessibilityCheck() else { return nil }
        return Self.accessibilityGuidance
    }

    /// 命令输出是否是「没有辅助功能权限」的错误（System Events 1002）。
    static func isAccessibilityDenied(output: String) -> Bool {
        output.contains("(1002)") || output.contains("不允许发送按键") || output.contains("not allowed to send keystrokes")
    }

    /// 最终会被执行的命令（自定义方式直接使用用户填写的内容）。
    var resolvedCommand: String {
        switch method {
        case .customCommand: return customCommand
        default: return method.command ?? ""
        }
    }

    /// 命令是否可执行：非空且自定义方式已填写。
    var isCommandValid: Bool {
        !resolvedCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @discardableResult
    func lock() -> Bool {
        guard isCommandValid else {
            DiagnosticsLog.shared.append(.error, "锁屏命令为空（\(method.title)）")
            return false
        }
        if let issue = permissionIssue() {
            DiagnosticsLog.shared.append(.error, "无法锁定：\(issue)")
            return false
        }
        let command = resolvedCommand

        DiagnosticsLog.shared.append(.info, "执行锁屏：\(method.title)")
        let process = Process()
        process.launchPath = "/bin/sh"
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.terminationHandler = { finished in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = (String(data: data, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if finished.terminationStatus == 0 {
                DiagnosticsLog.shared.append(.info, "锁屏命令执行成功")
            } else {
                // 预检通过但仍被拒（例如自定义命令里也用了 System Events），补上处理指引。
                let hint = Self.isAccessibilityDenied(output: output) ? "\n" + Self.accessibilityGuidance : ""
                DiagnosticsLog.shared.append(
                    .error,
                    "锁屏命令失败（退出码 \(finished.terminationStatus)）：\(output.isEmpty ? "无输出" : output)\(hint)"
                )
            }
        }
        do {
            try process.run()
        } catch {
            DiagnosticsLog.shared.append(.error, "锁屏失败：\(error.localizedDescription)")
            return false
        }
        return true
    }

    /// 点亮显示器（模拟一次用户活动），用于靠近时的「先唤醒、再由系统解锁」。
    @discardableResult
    static func wakeDisplay(seconds: Int = 1) -> Bool {
        let process = Process()
        process.launchPath = "/usr/bin/caffeinate"
        process.arguments = ["-u", "-t", "\(seconds)"]
        do {
            try process.run()
            DiagnosticsLog.shared.append(.info, "点亮显示器")
            return true
        } catch {
            DiagnosticsLog.shared.append(.error, "点亮显示器失败：\(error.localizedDescription)")
            return false
        }
    }
}
