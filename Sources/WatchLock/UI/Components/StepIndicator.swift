import SwiftUI

/// 引导步骤指示器：圆点 + 连接线 + 步骤名。
struct StepIndicator: View {
    let titles: [String]
    let current: Int

    var body: some View {
        HStack(alignment: .top, spacing: WLSpacing.xs) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                VStack(spacing: WLSpacing.xxs) {
                    ZStack {
                        Circle()
                            .fill(fill(index))
                            .frame(width: 18, height: 18)
                        if index < current {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .accessibilityHidden(true)
                        } else {
                            Text("\(index + 1)")
                                .font(.caption2.bold())
                                .foregroundStyle(index == current ? Color.white : Color.secondary)
                        }
                    }
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(index == current ? Color.primary : Color.secondary)
                }
                .accessibilityElement()
                .accessibilityLabel("第 \(index + 1) 步 \(title)")
                .accessibilityValue(index == current ? "当前步骤" : (index < current ? "已完成" : "未开始"))

                if index < titles.count - 1 {
                    Capsule(style: .continuous)
                        .fill(index < current ? WLColor.success.opacity(0.6) : WLColor.track)
                        .frame(height: 2)
                        .padding(.top, 8)
                        .accessibilityHidden(true)
                }
            }
        }
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
        .accessibilityValue(isSelected ? "已选中" : "未选中")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: WLRadius.sm, style: .continuous)
    }
}
