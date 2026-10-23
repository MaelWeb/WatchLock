import SwiftUI

/// 设备卡片：图标在上、名称在下，参考隔空投送的设备网格。
///
/// 整张卡片就是一个按钮（点击 = 绑定 / 添加），不再有单独的操作按钮；
/// 自定义名称与图标藏在右键菜单、悬停时出现的铅笔，以及 VoiceOver 的自定义操作里。
struct DeviceTile: View {
    /// 卡片角标：说明点击会发生什么，或当前所处状态。
    enum Badge: Equatable {
        /// 已绑定 / 已选中。
        case selected
        /// 点击会添加（辅助设备）。
        case add
    }

    let deviceID: String
    let label: DeviceLabel
    /// 实时信号；nil 表示不显示信号条。
    var signal: Signal?
    var badge: Badge?
    /// 悬停提示（开发者模式下会附带识别依据）。
    var help: String
    /// 非 nil 时，点击先弹确认框，确认后才执行 `action`（用于绑定这类会改动设置的操作）。
    var confirmation: Confirmation?
    let action: () -> Void

    /// 二次确认框的文案。
    struct Confirmation {
        let title: String
        let message: String
        let confirmTitle: String
    }

    struct Signal {
        let rssi: Int
        let nearRSSI: Int
        let farRSSI: Int
    }

    @State private var isHovering = false
    @State private var isEditing = false
    @State private var isConfirming = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                // 已选中的卡片再点没有意义；不用 disabled，免得整张卡片被系统置灰。
                guard badge != .selected else { return }
                if confirmation != nil {
                    isConfirming = true
                } else {
                    action()
                }
            } label: {
                content
            }
            .buttonStyle(.plain)
            .help(help)
            .accessibilityLabel(label.name)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(badge == .selected ? "" : help)
            .accessibilityAddTraits(badge == .selected ? .isSelected : [])
            .accessibilityAction(named: Text("自定义名称和图标")) { isEditing = true }

            editButton
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("自定义名称和图标…") { isEditing = true }
        }
        .deviceEditorPopover(isPresented: $isEditing, deviceID: deviceID, currentName: label.name)
        .confirmationDialog(
            confirmation?.title ?? "",
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            if let confirmation {
                Button(confirmation.confirmTitle, action: action)
                Button("取消", role: .cancel) {}
            }
        } message: {
            if let confirmation { Text(confirmation.message) }
        }
    }

    /// 悬停提示。开发者模式下附带识别依据（名称 / 厂商数据等），普通用户不展示这些调试信息。
    static func help(_ base: String, for device: DiscoveredWatch, extra: String? = nil) -> String {
        guard DeveloperMode.isEnabled else { return base }
        let reasons = device.matchReasons.isEmpty
            ? String(localized: "未命中识别规则（可拿远 / 靠近观察信号变化辨认）")
            : device.matchReasons.sorted().joined(separator: " · ")
        return [base, reasons, extra].compactMap { $0 }.joined(separator: "\n")
    }

    // MARK: - 内容

    private var content: some View {
        VStack(spacing: WLSpacing.sm) {
            iconPlate
            Text(label.name)
                .font(WLFont.caption)
                .multilineTextAlignment(.center)
                .lineLimit(WLSize.deviceNameLines, reservesSpace: true)
                .frame(maxWidth: .infinity)
            if let signal {
                SignalMeter(rssi: Double(signal.rssi), nearRSSI: signal.nearRSSI, farRSSI: signal.farRSSI)
            }
        }
        .padding(.vertical, WLSpacing.sm)
        .padding(.horizontal, WLSpacing.xs)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: WLRadius.md, style: .continuous)
                .fill(isHovering ? Color.primary.opacity(0.08) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: WLRadius.md, style: .continuous))
    }

    private var iconPlate: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(badge == .selected ? WLColor.success.opacity(0.18) : Color.primary.opacity(0.08))
                .overlay {
                    Circle().strokeBorder(badge == .selected ? WLColor.success : Color.clear, lineWidth: 2)
                }
                .frame(width: WLSize.deviceIconPlate, height: WLSize.deviceIconPlate)
                .overlay {
                    Image(systemName: label.kind.symbolName)
                        .font(.system(size: WLSize.deviceIconGlyph))
                        .foregroundStyle(badge == .selected ? WLColor.success : Color.primary)
                        .accessibilityHidden(true)
                }

            if let badgeSymbol {
                Image(systemName: badgeSymbol)
                    .font(.system(size: WLSize.deviceBadgeGlyph))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, badge == .selected ? WLColor.success : WLColor.accent)
                    .accessibilityHidden(true)
            }
        }
    }

    private var badgeSymbol: String? {
        switch badge {
        case .selected: return "checkmark.circle.fill"
        case .add: return "plus.circle.fill"
        case nil: return nil
        }
    }

    /// 悬停时才出现，平时不占视觉；键盘 / VoiceOver 用户走右键菜单或自定义操作。
    @ViewBuilder
    private var editButton: some View {
        if isHovering {
            Button {
                isEditing = true
            } label: {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: WLSize.deviceBadgeGlyph))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.secondary, Color.primary.opacity(0.08))
            }
            .buttonStyle(.plain)
            .help("自定义名称和图标")
            .accessibilityHidden(true)
            .padding(WLSpacing.xs)
        }
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        if badge == .selected { parts.append(String(localized: "已绑定")) }
        if let signal {
            let level = SignalMeter.level(rssi: Double(signal.rssi), nearRSSI: signal.nearRSSI, farRSSI: signal.farRSSI)
            parts.append(level > 0
                ? String(localized: "信号 \(level) 格，共 \(SignalMeter.levelCount) 格")
                : String(localized: "无信号"))
        }
        return parts.joined(separator: "，")
    }
}

extension DeviceTile.Confirmation {
    /// 绑定确认：已绑定了别的设备时要明说「会替换」，并提醒绑定后的自动校准需要手表在身边。
    @MainActor
    static func bind(deviceName: String, replacing currentName: String?) -> DeviceTile.Confirmation {
        let calibration = String(localized: "绑定后会用约 10 秒的信号自动校准距离阈值，请让手表保持在身边。")
        let message = currentName.map {
            String(localized: "将替换当前绑定的「\($0)」。") + calibration
        } ?? calibration
        return DeviceTile.Confirmation(
            title: String(localized: "绑定「\(deviceName)」？"),
            message: message,
            confirmTitle: String(localized: "绑定")
        )
    }
}

/// 设备卡片网格：按宽度自适应列数，行内顶对齐。
struct DeviceGrid<Content: View>: View {
    @ViewBuilder var content: () -> Content

    private let columns = [
        GridItem(.adaptive(minimum: WLSize.deviceTileMinWidth), spacing: WLSpacing.sm, alignment: .top)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .center, spacing: WLSpacing.sm) {
            content()
        }
        .frame(maxWidth: .infinity)
    }
}
