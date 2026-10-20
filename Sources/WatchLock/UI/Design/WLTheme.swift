import SwiftUI

/// 设计 token：间距、圆角、语义色。
///
/// 视图里一律引用这里的常量，不要再写裸数字（见 `docs/ui-design.md` §3 与
/// `.codebuddy/rules/watchlock-ui.md`）。
enum WLSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum WLRadius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 14
}

/// 字体 token：对应设计稿的三档层级（见 `docs/ui-design.md` §3）。
///
/// 注意 macOS 的文本样式字号与 iOS 不同：`.headline` 是 13、`.caption` 是 10，
/// 直接用会比设计稿（15 / 13 / 11）整体偏小，所以选用字号刚好对得上的样式。
enum WLFont {
    /// 状态标题：15 semibold（`.title3`）。
    static let statusTitle = Font.title3.weight(.semibold)
    /// 正文 / 主要数值：13（`.body`）。
    static let body = Font.body
    /// 次要说明：11（`.subheadline`），通常配合 `.secondary`。
    static let caption = Font.subheadline
}

/// 语义色：集中定义，便于统一适配深色模式与增强对比度。
/// 视图里不要直接写 `.green` / `.orange` / `.red`。
enum WLColor {
    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red
    static let neutral = Color.secondary
    static let accent = Color.accentColor

    /// 未填充部分的底色（信号条、进度槽等）。
    static let track = Color.primary.opacity(0.12)
}

/// 卡片强调色，用于提示风险等级。
enum WLCardTint {
    case plain
    case warning
    case danger

    var stroke: Color {
        switch self {
        case .plain: return .clear
        case .warning: return WLColor.warning.opacity(0.45)
        case .danger: return WLColor.danger.opacity(0.45)
        }
    }
}

private struct WLCardModifier: ViewModifier {
    var tint: WLCardTint
    var insets: EdgeInsets

    func body(content: Content) -> some View {
        content
            .padding(insets)
            .background(.quaternary, in: shape)
            .overlay { shape.strokeBorder(tint.stroke, lineWidth: tint == .plain ? 0 : 1) }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: WLRadius.md, style: .continuous)
    }
}

extension View {
    /// 统一卡片容器。默认无描边，`tint` 用于强调注意 / 风险。
    func wlCard(tint: WLCardTint = .plain, padding: CGFloat = WLSpacing.md) -> some View {
        modifier(WLCardModifier(
            tint: tint,
            insets: EdgeInsets(top: padding, leading: padding, bottom: padding, trailing: padding)
        ))
    }

    /// 横纵内边距不同的紧凑卡片，用于单行内容（开关行、提示条：横 12 / 竖 8）。
    func wlCard(tint: WLCardTint = .plain, horizontal: CGFloat, vertical: CGFloat) -> some View {
        modifier(WLCardModifier(
            tint: tint,
            insets: EdgeInsets(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal)
        ))
    }

    /// 多段内容共用一张卡底：本身不留内边距，各段自带留白，段与段之间用 `CardSection` 的发丝线分隔
    /// （系统设置 / 控制中心的分组观感）。
    func wlCardGroup(tint: WLCardTint = .plain) -> some View {
        modifier(WLCardModifier(tint: tint, insets: EdgeInsets()))
    }
}
