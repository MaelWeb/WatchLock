import Foundation
import LocalAuthentication

/// 系统「锁定屏幕」要求输入密码的延迟，来自 `sysadminctl -screenLock status`。
///
/// 依据：旧实现读 `com.apple.screensaver askForPassword`，该键在新系统上并不存在
/// （macOS 26.6.1 实测 `defaults read com.apple.screensaver` 只有 `tokenRemovalAction`，
/// 社区也报告 Sequoia 起该设置改由「系统设置」接管），会让已设为「立即」的机器误报缺失。
/// 输出文案取自 `/usr/sbin/sysadminctl` 二进制内的字符串：
/// `screenLock is off` / `screenLock delay is immediate` / `screenLock delay is %d seconds`
/// / `Unknown state for screenLock (%@)`。
enum ScreenLockDelay: Equatable {
    case immediate
    case seconds(Int)
    case off
    /// 无法识别的输出（命令失败、系统改了文案）。**不能据此判定缺失**，否则会重现误报。
    case unknown

    static func parse(_ output: String) -> ScreenLockDelay {
        if output.contains("screenLock delay is immediate") { return .immediate }
        if output.contains("screenLock is off") { return .off }
        if let range = output.range(of: #"screenLock delay is \d+ seconds"#, options: .regularExpression) {
            let digits = output[range].filter(\.isNumber)
            if let value = Int(digits) { return .seconds(value) }
        }
        return .unknown
    }
}

/// 系统是否报告「附近有可用于认证的 Apple Watch」。
enum CompanionAvailability: Equatable {
    case available
    /// 附带系统返回的错误（`domain#code`），仅用于诊断日志。
    case unavailable(String)
}

/// 「系统自动解锁」的前置条件探测。
enum AutoUnlockPrerequisites {
    static let screenLockGuidance = String(localized: "「系统设置 → 锁定屏幕」中未设为「立即」要求输入密码")
    static let companionGuidance =
        String(localized: "系统未报告附近有可用于认证的 Apple Watch（请确认手表已解锁并佩戴，且已在「触控 ID 与密码」中开启「使用 Apple Watch 解锁」）")

    /// 纯函数：由探测结果得出缺失项。`unknown` 一律不报，宁可漏报也不误报。
    static func missing(lockDelay: ScreenLockDelay, companion: CompanionAvailability) -> [String] {
        var result: [String] = []
        switch lockDelay {
        case .seconds, .off: result.append(screenLockGuidance)
        case .immediate, .unknown: break
        }
        if case .unavailable = companion { result.append(companionGuidance) }
        return result
    }

    /// 读取系统探测结果并给出缺失项（会启动子进程，约数毫秒）。
    static func evaluate() -> [String] {
        let delay = readLockDelay()
        let companion = readCompanionAvailability()
        if case .unavailable(let detail) = companion {
            DiagnosticsLog.shared.append(.info, String(localized: "Apple Watch 认证探测未通过（\(detail)）"))
        }
        if delay == .unknown {
            DiagnosticsLog.shared.append(.info, String(localized: "无法识别系统锁屏延迟设置，跳过该项前置条件检查"))
        }
        return missing(lockDelay: delay, companion: companion)
    }

    static func readLockDelay() -> ScreenLockDelay {
        ScreenLockDelay.parse(Shell.run("/usr/sbin/sysadminctl", arguments: ["-screenLock", "status"]))
    }

    /// 依据 Apple 文档：`deviceOwnerAuthenticationWithCompanion`（macOS 15+）在找不到附近已配对的配套设备时
    /// 返回 `LAErrorCompanionNotAvailable`；macOS 14 只有已在 15 中改名的 `...WithWatch`。
    /// `canEvaluatePolicy` 只做可用性判断，不会弹出认证界面。
    static func readCompanionAvailability() -> CompanionAvailability {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(companionPolicy, error: &error) { return .available }
        let detail = error.map { "\($0.domain)#\($0.code)" } ?? String(localized: "未知错误")
        return .unavailable(detail)
    }

    private static var companionPolicy: LAPolicy {
        if #available(macOS 15.0, *) { return .deviceOwnerAuthenticationWithCompanion }
        return .deviceOwnerAuthenticationWithWatch
    }
}
