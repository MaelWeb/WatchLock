import SwiftUI

// MARK: - 状态卡

/// 状态卡：状态图标 + 状态标题 + 副标题，底部由调用方追加指标行。
///
/// 图标与菜单栏同源（`StatusIcon` → `MenuBarIcon`），不再单独指定 SF Symbol。
struct StatusCard<Footer: View>: View {
    let status: ProximityStatus
    let title: String
    let subtitle: String
    let tint: Color
    @ViewBuilder var footer: Footer

    init(
        status: ProximityStatus,
        title: String,
        subtitle: String,
        tint: Color,
        @ViewBuilder footer: () -> Footer
    ) {
        self.status = status
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.footer = footer()
    }

    var body: some View {
        // 标题区与指标区之间 12，指标区内部行距 8（设计稿 01-menubar）。
        VStack(alignment: .leading, spacing: WLSpacing.md) {
            // 位图图标没有文字基线，改为顶部对齐（图标高度与标题行高相当）。
            HStack(alignment: .top, spacing: WLSpacing.sm) {
                StatusIcon(status: status, tint: tint)
                VStack(alignment: .leading, spacing: WLSpacing.xs) {
                    Text(title).font(WLFont.statusTitle)
                    Text(subtitle).font(WLFont.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: WLSpacing.sm) {
                footer
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wlCard()
    }
}

// MARK: - 指标行

/// 标签 + 数值行，数值统一等宽数字。默认是次要说明（11pt、次要色）。
struct MetricRow: View {
    let label: String
    let value: String
    var valueColor: Color?

    var body: some View {
        HStack(spacing: WLSpacing.sm) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: WLSpacing.sm)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(valueColor ?? .secondary)
        }
        .font(WLFont.caption)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

// MARK: - 按钮

enum WLButtonRole {
    case primary
    case secondary
    case danger
}

/// 三档样式的统一按钮，避免各处临时拼 `.buttonStyle`。
struct WLButton: View {
    let title: String
    var systemImage: String?
    var role: WLButtonRole = .secondary
    var help: String?
    var isDisabled = false
    /// 固定宽度；`nil` 时由外层容器决定（常用于等宽按钮行）。
    var width: CGFloat?
    let action: () -> Void

    init(
        _ title: String,
        systemImage: String? = nil,
        role: WLButtonRole = .secondary,
        help: String? = nil,
        isDisabled: Bool = false,
        width: CGFloat? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.help = help
        self.isDisabled = isDisabled
        self.width = width
        self.action = action
    }

    var body: some View {
        switch role {
        case .primary:
            styledButton.buttonStyle(.borderedProminent).frame(width: width)
        case .secondary:
            styledButton.buttonStyle(.bordered).frame(width: width)
        case .danger:
            styledButton.buttonStyle(.bordered).tint(WLColor.danger).frame(width: width)
        }
    }

    @ViewBuilder
    private var styledButton: some View {
        if let help {
            baseButton.help(help)
        } else {
            baseButton
        }
    }

    private var baseButton: some View {
        Button(role: role == .danger ? .destructive : nil) {
            action()
        } label: {
            WLButtonLabel(title, systemImage: systemImage)
        }
        .disabled(isDisabled)
    }
}

/// `WLButton` 的标签外观（图标 + 文字，撑满可用宽度）。
///
/// 抽出来是为了让 `Menu` 之类不能直接用 `WLButton` 的控件也能和按钮保持同一尺寸与间距，
/// 例如菜单栏面板里并排的「立即锁定 / 暂停 / 设置…」。
struct WLButtonLabel: View {
    let title: String
    var systemImage: String?

    init(_ title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: WLSpacing.xs) {
            if let systemImage {
                Image(systemName: systemImage).accessibilityHidden(true)
            }
            Text(title).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, WLSpacing.xxs)
    }
}

// MARK: - 统计小卡

struct StatChip: View {
    let label: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        VStack(spacing: WLSpacing.xxs) {
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, WLSpacing.sm)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: WLRadius.sm, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

// MARK: - 分组卡片

/// 非 `Form` 页面使用的分组容器（校准 / 诊断 / 设备等）。
struct FormCard<Content: View>: View {
    let title: String?
    let subtitle: String?
    @ViewBuilder var content: Content

    init(title: String? = nil, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WLSpacing.sm) {
            if let title {
                Text(title).font(.headline)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wlCard()
    }
}

// MARK: - 空态

/// 统一空态。文案由调用方按上下文给出，列表为空时**替换**列表区域，不用 overlay 叠加。
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
    }
}
