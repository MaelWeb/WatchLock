import SwiftUI

/// 面板内的状态图标：与菜单栏同一套代码绘制的五态图标（`MenuBarIcon`），
/// 保证「菜单栏里看到什么，面板里就是什么」，不再用 SF Symbol 另起一套。
///
/// 图标本身是模板图，颜色由 `tint` 决定（菜单栏里由系统着色，面板里按语义色着色）。
struct StatusIcon: View {
    let status: ProximityStatus
    let tint: Color
    /// 边长；默认 20，与状态标题（15pt semibold）的行高相当，顶部对齐时视觉居中。
    var size: CGFloat = 20

    var body: some View {
        Image(nsImage: MenuBarIcon.image(for: status))
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(foreground)
            // 状态文字已经表达了同样的信息，图标仅作视觉强化。
            .accessibilityHidden(true)
    }

    /// 「已关闭」图标自带 `MenuBarIcon.disabledAlpha` 的整体淡化，
    /// 再叠加次要色会变得几乎看不见，所以改用主色承载，淡化效果由图标本身提供。
    private var foreground: Color {
        status == .disabled ? Color.primary : tint
    }
}
