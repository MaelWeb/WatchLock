import Foundation

/// 靠近时的解锁策略。
enum UnlockStrategy: String, CaseIterable, Identifiable {
    /// 仅点亮显示器，依赖系统自带的「用 Apple Watch 解锁」。
    case wakeOnly
    /// 点亮显示器并引导/校验系统自动解锁是否已开启。
    case systemAutoUnlock
    /// 由本应用托管登录密码并模拟键入（高风险，默认关闭）。
    case managedPassword

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wakeOnly: return String(localized: "仅唤醒屏幕")
        case .systemAutoUnlock: return String(localized: "系统自动解锁（推荐）")
        case .managedPassword: return String(localized: "托管密码自动输入（高风险）")
        }
    }

    var detail: String {
        switch self {
        case .wakeOnly:
            return String(localized: "靠近时点亮显示器，后续解锁动作交给 macOS 原生流程（需要已开启「使用 Apple Watch 解锁」）。")
        case .systemAutoUnlock:
            return String(localized: "在唤醒的基础上检查系统自动解锁前置条件，缺失时给出引导，不接触用户密码。")
        case .managedPassword:
            return String(localized: "将登录密码存入钥匙串，靠近时通过辅助功能模拟键入完成解锁。需要辅助功能权限，存在密码泄漏风险，仅建议在个人设备上开启。")
        }
    }

    var isRisky: Bool { self == .managedPassword }
}
