import SwiftUI

/// 设置窗口详情区的统一容器：统一内边距、最小宽度、超出一屏可滚动。
///
/// 卡片式页面（设备 / 校准）用它；`Form` 页面（通用 / 解锁）自身可滚动，不再套一层
/// `ScrollView`（规范：禁止嵌套滚动）。
struct SettingsDetail<Content: View>: View {
    var minWidth: CGFloat = 460
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            content()
                .frame(minWidth: minWidth, maxWidth: .infinity, alignment: .topLeading)
                .padding(WLSpacing.lg)
        }
        .frame(minWidth: minWidth)
    }
}

/// 卡片内的分隔线（比 `Divider()` 更贴合卡片内边距）。
struct CardDivider: View {
    var body: some View {
        Divider()
            .padding(.vertical, WLSpacing.xxs)
    }
}

/// 带图标的小标题，用于卡片内的分区（例如「调试」「误锁反馈」）。
struct CardSectionHeader: View {
    let title: String
    let systemImage: String
    var tint: Color = WLColor.accent

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(tint)
    }
}
