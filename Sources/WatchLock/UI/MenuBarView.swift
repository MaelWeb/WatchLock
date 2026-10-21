import AppKit
import SwiftUI

/// 菜单栏面板。
///
/// 设计要点（见 `docs/ui-design.md` §5.1）：状态优先、主操作收敛为 3 个、
/// 调试与退出收进「更多」以降低误触。
struct MenuBarView: View {
    @EnvironmentObject private var session: AppSession
    @ObservedObject private var settings = SettingsStore.shared

    @State private var confirmingLock = false

    private let panelWidth: CGFloat = 340

    var body: some View {
        // 区块间距 12。标题行（含主开关）、告警、三块指标瓦片按设计稿 D 直接铺在面板上，
        // 不再套状态卡。
        VStack(alignment: .leading, spacing: WLSpacing.md) {
            status
            // 上下文提示（暂停 / 误锁反馈）在主操作之上，触发时才出现，不占常驻空间。
            pauseRow
            falseLockRow
            actions
            footerGroup
        }
        .padding(WLSpacing.lg)
        .frame(width: panelWidth)
        .confirmationDialog("立即锁定屏幕？", isPresented: $confirmingLock) {
            Button("锁定", role: .destructive) { session.lockNow() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("等同于 ⌃⌘Q，锁定后需要重新验证身份。可在「设置 → 通用」关闭此确认。")
        }
    }

    // MARK: - 状态

    /// 标题行 + 告警 + 指标瓦片，不再套状态卡容器：层级靠留白，不靠底色（设计稿 D）。
    private var status: some View {
        VStack(alignment: .leading, spacing: WLSpacing.md) {
            VStack(alignment: .leading, spacing: WLSpacing.sm) {
                titleRow
                if let message = warningMessage {
                    scannerWarning(message)
                }
            }
            VStack(alignment: .leading, spacing: WLSpacing.sm) {
                metricTiles
                if let reason = session.lastLockReason, let date = session.lastLockAt {
                    MetricRow(label: String(localized: "上次锁定"), value: LastLockSummary.text(reason: reason, at: date))
                }
            }
        }
    }

    /// 状态图标 + 标题 / 设备名在左，主开关在右（开关下方一行小字说明它管什么）。
    private var titleRow: some View {
        // 位图图标没有文字基线，顶部对齐（图标高度与标题行高相当）。
        HStack(alignment: .top, spacing: WLSpacing.sm) {
            StatusIcon(status: session.status, tint: statusTint)
            VStack(alignment: .leading, spacing: WLSpacing.xs) {
                Text(session.status.title).font(WLFont.statusTitle)
                Text(subtitle).font(WLFont.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: WLSpacing.sm)
            masterToggle
        }
    }

    /// 三块指标：信号 / 距离 / 更新。信号条按当前阈值分级，与是否会锁屏同口径。
    private var metricTiles: some View {
        HStack(spacing: WLSpacing.sm) {
            MetricTile(
                title: String(localized: "信号"),
                reading: MenuBarMetrics.signal(rssi: session.smoothedRSSI)
            ) {
                SignalMeter(rssi: session.smoothedRSSI, nearRSSI: settings.nearRSSI, farRSSI: settings.farRSSI)
            }
            MetricTile(
                title: String(localized: "距离"),
                reading: MenuBarMetrics.distance(meters: session.estimatedDistance)
            )
            MetricTile(
                title: String(localized: "更新"),
                reading: MenuBarMetrics.updated(since: session.lastSeen)
            )
        }
    }

    /// 告警，按优先级只显示一条：
    /// 扫描器自身的问题 > 因会议 / 演示暂缓锁定 > 因辅助设备暂缓锁定（后两者安全相关：此刻不会自动锁屏）> 未绑定手表。
    /// 模拟信号期间不提示未绑定（调试流程不需要绑定）。
    private var warningMessage: String? {
        if let message = session.scannerMessage { return message }
        if let note = session.lockDeferralNote { return note }
        if let note = session.fusionNote { return note }
        if settings.boundWatchID == nil, session.simulatedRSSI == nil {
            return String(localized: "尚未绑定手表，自动锁定暂不生效（设置 → 设备）")
        }
        return nil
    }

    /// 副标题：设备名。「最后更新」已有自己的瓦片。
    private var subtitle: String {
        settings.boundWatchName ?? String(localized: "尚未绑定手表")
    }

    private var statusTint: Color {
        switch session.status {
        case .near: return WLColor.success
        case .far: return WLColor.warning
        case .unknown: return WLColor.neutral
        case .paused, .disabled: return WLColor.neutral
        }
    }

    private func scannerWarning(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(WLFont.caption)
            .foregroundStyle(WLColor.warning)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 主开关与暂停

    /// 标题行右侧的主开关：开关 + 下方一行小字「自动锁定」。
    ///
    /// `Toggle` 的 label 在 `.switch` 样式下会被并排放在开关旁（Form 之外），所以隐藏 label，
    /// 另放一行小字；小字对辅助功能隐藏，由开关自己的 `启用自动锁定` 朗读。
    private var masterToggle: some View {
        VStack(alignment: .trailing, spacing: WLSpacing.xxs) {
            Toggle("启用自动锁定", isOn: Binding(
                get: { settings.isEnabled },
                set: { setEnabled($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .help("关闭后不再自动锁定，菜单栏只显示状态")

            Text("自动锁定")
                .font(WLFont.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private func setEnabled(_ value: Bool) {
        settings.isEnabled = value
        session.refreshConfig()
    }

    @ViewBuilder
    private var pauseRow: some View {
        if settings.isTrustedPlacePausing, !settings.isManuallyPaused(now: Date()) {
            trustedPlaceRow
        } else if settings.isPaused {
            HStack(spacing: WLSpacing.sm) {
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(WLColor.warning)
                    .accessibilityHidden(true)
                Text("已暂停")
                    .font(WLFont.caption)
                    .foregroundStyle(.secondary)
                if let until = settings.pauseUntil {
                    Text("至 \(until.formatted(date: .omitted, time: .shortened))")
                        .font(WLFont.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: WLSpacing.xs)
                Button("恢复") { session.resume() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("恢复自动锁定")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .wlCard(tint: .warning, horizontal: WLSpacing.md, vertical: WLSpacing.sm)
        }
    }

    /// 信任场所内的自动暂停：与手动暂停同款提示条，「恢复」只对本次停留有效，离开该网络后重新按场所判断。
    private var trustedPlaceRow: some View {
        HStack(spacing: WLSpacing.sm) {
            Image(systemName: "mappin.circle.fill")
                .foregroundStyle(WLColor.warning)
                .accessibilityHidden(true)
            Text("在「\(settings.activeTrustedPlaceName ?? "")」，已暂停")
                .font(WLFont.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: WLSpacing.xs)
            Button("恢复") { session.resume() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("在这个网络里也恢复自动锁定，直到你离开")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wlCard(tint: .warning, horizontal: WLSpacing.md, vertical: WLSpacing.sm)
    }

    // MARK: - 主操作

    private var actions: some View {
        HStack(alignment: .center, spacing: WLSpacing.sm) {
            WLButton(
                String(localized: "立即锁定"),
                systemImage: "lock.fill",
                help: settings.confirmBeforeLock ? String(localized: "锁定前会先确认") : String(localized: "点按后立即锁定屏幕（⌃⌘Q）")
            ) {
                if settings.confirmBeforeLock {
                    confirmingLock = true
                } else {
                    session.lockNow()
                }
            }

            pauseMenu

            Button {
                SettingsWindow.present(session: session)
            } label: {
                WLButtonLabel(String(localized: "设置…"), systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .keyboardShortcut(",", modifiers: .command)
            .help("打开设置窗口（⌘,）")
        }
    }

    /// 「暂停」需要下拉选项：用 `.button` 菜单样式 + `.bordered`，外观、尺寸与旁边两个按钮完全一致
    /// （原来的 `.borderlessButton` 不渲染按钮底，宽度也与另外两个不等）。
    private var pauseMenu: some View {
        Menu {
            Button("暂停 15 分钟") { session.pause(minutes: 15) }
            Button("暂停 1 小时") { session.pause(minutes: 60) }
            Button("暂停 4 小时") { session.pause(minutes: 240) }
        } label: {
            WLButtonLabel(String(localized: "暂停"), systemImage: "pause.fill")
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity)
        .help("临时停止自动锁定")
    }

    // MARK: - 上下文行

    @ViewBuilder
    private var falseLockRow: some View {
        if session.falseLockFeedbackAvailable || session.tuningMessage != nil {
            VStack(alignment: .leading, spacing: WLSpacing.sm) {
                if session.falseLockFeedbackAvailable {
                    HStack(spacing: WLSpacing.sm) {
                        Image(systemName: "hand.raised.fill")
                            .foregroundStyle(WLColor.warning)
                            .accessibilityHidden(true)
                        Text("刚才这次是误锁？")
                            .font(WLFont.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: WLSpacing.xs)
                        Button("记为误锁") { session.reportFalseLock() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("记为一次误锁，应用会按误锁率自动放宽判定")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .wlCard(tint: .warning, horizontal: WLSpacing.md, vertical: WLSpacing.sm)
                }

                if let message = session.tuningMessage {
                    Text(message)
                        .font(WLFont.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - 次要入口

    /// 分隔线 + 「更多」。分隔线与上方区块间距 12，与下方入口间距 8（设计稿）。
    private var footerGroup: some View {
        VStack(alignment: .leading, spacing: WLSpacing.sm) {
            Divider()
            footer
        }
    }

    private var footer: some View {
        HStack(spacing: WLSpacing.sm) {
            moreMenu

            Spacer(minLength: WLSpacing.sm)

            if let rssi = session.simulatedRSSI {
                Text(rssi == -127 ? String(localized: "模拟：信号丢失") : String(localized: "模拟：\(rssi) dBm"))
                    .font(WLFont.caption)
                    .foregroundStyle(WLColor.warning)
            }
        }
    }

    /// 用 `.plain` 按钮样式 + 自绘标签，去掉 `.borderlessButton` 自带的内边距，
    /// 让「更多」与卡片左边缘对齐。
    private var moreMenu: some View {
        Menu {
            if DeveloperMode.isEnabled {
                Section("模拟信号") {
                    Button("在身边 (-50 dBm)") { session.startSimulating(rssi: -50) }
                    Button("边界 (-65 dBm)") { session.startSimulating(rssi: -65) }
                    Button("离开 (-85 dBm)") { session.startSimulating(rssi: -85) }
                    Button("信号丢失") { session.simulateSignalLoss() }
                    Button("停止模拟") { session.stopSimulating() }
                        .disabled(session.simulatedRSSI == nil)
                }
            }
            Button("退出 WatchLock") { NSApp.terminate(nil) }
        } label: {
            HStack(spacing: WLSpacing.xs) {
                Text("更多")
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.vertical, WLSpacing.xxs)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(DeveloperMode.isEnabled ? String(localized: "调试与退出") : String(localized: "更多操作"))
    }
}
