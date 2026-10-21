import Foundation

/// 开发者模式：只给开发 / 排查用，**普通用户在界面上看不到任何入口**。
///
/// 受它控制的内容：模拟信号子菜单、广播抓包、设备列表的广播类型 / 广播详情、调试说明与日志路径。
///
/// 打开方式（任选其一）：
/// - Debug 构建（`swift build` / `swift run`）自动开启；
/// - 带环境变量启动：`WATCHLOCK_DEVELOPER=1`；
/// - `defaults write <bundle id> developerMode -bool YES`（关闭用 `-bool NO`），重启应用后生效。
enum DeveloperMode {
    static let defaultsKey = "developerMode"

    static var isEnabled: Bool {
        #if DEBUG
        return true
        #else
        return resolve(environment: ProcessInfo.processInfo.environment, defaults: .standard)
        #endif
    }

    /// 非 Debug 构建下的判定；可注入环境与存储，便于单测。
    static func resolve(environment: [String: String], defaults: UserDefaults) -> Bool {
        if environment["WATCHLOCK_DEVELOPER"] == "1" { return true }
        return defaults.bool(forKey: defaultsKey)
    }
}
