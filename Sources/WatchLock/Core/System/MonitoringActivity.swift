import Foundation

/// 监听期间向系统声明「正在执行用户期望持续进行的工作」，避免菜单栏后台应用被 App Nap 限速。
///
/// 依据：Apple《Energy Efficiency Guide for Mac Apps》写明，非前台、窗口无更新、没有持有 IOKit /
/// `NSProcessInfo` 断言的应用是 App Nap 候选，会被降低进程优先级并限流定时器；
/// 声明用户发起的活动（`beginActivity`）会阻止系统把应用置入 App Nap。
/// WatchLock 是 `LSUIElement` 且无常驻窗口，正符合候选条件，而状态机依赖 1 秒定时器结算。
///
/// 选项取 `.userInitiatedAllowingIdleSystemSleep`：不阻止空闲系统睡眠。
/// 实测（2026-10-19，macOS 26.6.1，`pmset -g assertions`）：该选项不产生任何电源断言，
/// 而 `.userInitiated` 会产生 `PreventUserIdleSystemSleep`——所以这里必须用前者。
/// 注意：「不出现在 pmset 断言里」只说明不阻止睡眠，**不能**证明它已阻止 App Nap；
/// 阻止 App Nap 的依据是上述 Apple 文档（用户发起活动不会被置入 App Nap）。
///
/// 待真机验证：本应用在没有该防护时是否真的被 App Nap 限速（文档称 XPC 消息会让应用退出 App Nap，
/// CoreBluetooth 回调走 XPC，实际影响可能小于预期）。验证方法见 `DEVELOPMENT.md`。
final class MonitoringActivity {
    typealias Begin = (ProcessInfo.ActivityOptions, String) -> NSObjectProtocol
    typealias End = (NSObjectProtocol) -> Void

    static let options: ProcessInfo.ActivityOptions = .userInitiatedAllowingIdleSystemSleep
    static let reason = "WatchLock is monitoring Apple Watch proximity"

    private let begin: Begin
    private let end: End
    private var token: NSObjectProtocol?

    var isActive: Bool { token != nil }

    init(
        begin: @escaping Begin = { ProcessInfo.processInfo.beginActivity(options: $0, reason: $1) },
        end: @escaping End = { ProcessInfo.processInfo.endActivity($0) }
    ) {
        self.begin = begin
        self.end = end
    }

    /// 幂等：已持有时不重复声明。
    func start() {
        guard token == nil else { return }
        token = begin(Self.options, Self.reason)
        DiagnosticsLog.shared.append(.info, String(localized: "已声明监听活动（避免 App Nap 限速）"))
    }

    /// 幂等：未持有时无操作。
    func stop() {
        guard let token else { return }
        end(token)
        self.token = nil
        DiagnosticsLog.shared.append(.info, String(localized: "已结束监听活动声明"))
    }

    /// 按需求同步：需要时持有，不需要时释放。
    func setRequired(_ required: Bool) {
        if required { start() } else { stop() }
    }

    deinit {
        if let token { end(token) }
    }
}
