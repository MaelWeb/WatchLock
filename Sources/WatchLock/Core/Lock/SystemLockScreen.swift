import Foundation

/// 通过系统私有接口立即锁屏（免「辅助功能」权限）。
///
/// 菜单栏苹果菜单里的「锁定屏幕」最终调用的就是 `login.framework` 里的
/// `SACLockScreenImmediate`。它**没有公开文档**，随系统升级可能改名或被移除，所以：
/// - 只用 `dlopen` / `dlsym` 在运行时查找，不做编译期链接，找不到时优雅降级而不是崩溃；
/// - 返回值类型未公开，按 `Void` 声明并忽略（忽略返回值在 ABI 上是安全的）；
/// - 仅用于 GitHub Release 等非 App Store 渠道分发（私有 API 过不了 App Store 审核）。
enum SystemLockScreen {
    typealias LockFunction = @convention(c) () -> Void

    static let frameworkPath = "/System/Library/PrivateFrameworks/login.framework/login"
    static let symbolName = "SACLockScreenImmediate"

    /// 解析函数指针，**不调用**。
    static func resolve() -> LockFunction? {
        guard let handle = dlopen(frameworkPath, RTLD_LAZY),
              let symbol = dlsym(handle, symbolName) else {
            return nil
        }
        return unsafeBitCast(symbol, to: LockFunction.self)
    }

    /// 当前系统上这个接口是否可用（只解析符号，不会真的锁屏）。
    static var isAvailable: Bool {
        resolve() != nil
    }

    /// 立即锁屏；接口不可用时返回 `false`。
    @discardableResult
    static func lock() -> Bool {
        guard let function = resolve() else { return false }
        function()
        return true
    }
}
