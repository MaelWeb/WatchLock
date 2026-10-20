import SwiftUI

/// 引导步骤指示器：一排圆点，当前步骤拉长成胶囊，已完成为绿点。
///
/// 放在内容区底部、按钮行之上。比原先「圆点 + 连接线 + 步骤名」的顶栏更轻，
/// 把窗口上半部分让给插画与内容；步骤名仅保留给 VoiceOver（见调用处的 accessibilityLabel）。
struct StepIndicator: View {
    let titles: [String]
    let current: Int

    private enum Metrics {
        static let dot: CGFloat = 6
        static let currentWidth: CGFloat = 16
    }

    var body: some View {
        HStack(spacing: WLSpacing.sm - WLSpacing.xxs) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                Capsule(style: .continuous)
                    .fill(fill(index))
                    .frame(width: index == current ? Metrics.currentWidth : Metrics.dot, height: Metrics.dot)
                    .accessibilityElement()
                    .accessibilityLabel("第 \(index + 1) 步 \(title)")
                    .accessibilityValue(index == current ? String(localized: "当前步骤") : (index < current ? String(localized: "已完成") : String(localized: "未开始")))
            }
        }
        .animation(.easeOut(duration: 0.2), value: current)
        .frame(maxWidth: .infinity)
    }

    private func fill(_ index: Int) -> Color {
        if index < current { return WLColor.success }
        if index == current { return WLColor.accent }
        return WLColor.track
    }
}

/// 竖排单选卡（替换横排长标题按钮，避免挤压换行）。
struct RadioCard: View {
    let title: String
    var subtitle: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button { action() } label: {
            HStack(alignment: .firstTextBaseline, spacing: WLSpacing.sm) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? WLColor.accent : .secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: WLSpacing.xxs) {
                    Text(title).font(.callout)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(WLSpacing.sm)
            .background(.quaternary, in: shape)
            .overlay {
                shape.strokeBorder(isSelected ? WLColor.accent : .clear, lineWidth: isSelected ? 1.5 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? String(localized: "已选中") : String(localized: "未选中"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: WLRadius.sm, style: .continuous)
    }
}
