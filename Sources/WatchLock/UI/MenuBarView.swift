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
        // 区块间距 12；仅「状态卡 → 扫描告警 → 主开关」在出现告警时收紧到 8，
        // 让告警行贴着状态卡而不是漂在中间（设计稿 01-menubar 场景 3）。
        VStack(alignment: .leading, spacing: WLSpacing.md) {
            VStack(alignment: .leading, spacing: session.scannerMessage == nil ? WLSpacing.md : WLSpacing.sm) {
                status
                if let message = session.scannerMessage {
                    scannerWarning(message)
                }
                masterToggle
            }
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

    private var status: some View {
        StatusCard(
            symbol: session.status.symbolName,
            title: session.status.title,
            subtitle: subtitle,
            tint: statusTint
        ) {
            HStack(spacing: WLSpacing.sm) {
                SignalMeter(
                    rssi: session.smoothedRSSI,
                    nearRSSI: settings.nearRSSI,
                    farRSSI: settings.farRSSI
                )
                Text(rssiText)
                    .font(WLFont.body.monospacedDigit())
                Spacer(minLength: WLSpacing.sm)
                Text(distanceText)
                    .font(WLFont.body.monospacedDigit())
            }
            MetricRow(label: "最后更新", value: lastSeenText)
        }
    }

    private var subtitle: String {
        if let name = settings.boundWatchName { return name }
        return "尚未绑定手表"
    }

    private var statusTint: Color {
        switch session.status {
        case .near: return WLColor.success
        case .far: return WLColor.warning
        case .unknown: return WLColor.neutral
        case .paused, .disabled: return WLColor.neutral
        }
    }

    private var rssiText: String {
        session.smoothedRSSI < 0
            ? String(format: "%.0f dBm", session.smoothedRSSI)
            : "无信号"
    }

    private var distanceText: String {
        session.estimatedDistance > 0
            ? String(format: "约 %.1f 米", session.estimatedDistance)
            : "距离未知"
    }

    private var lastSeenText: String {
        guard let date = session.lastSeen else { return "—" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(seconds) 秒前" }
        return "\(seconds / 60) 分钟前"
    }

    private func scannerWarning(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(WLFont.caption)
            .foregroundStyle(WLColor.warning)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 主开关与暂停

    /// 文字在左、开关在右（设计稿）。
    ///
    /// 不能把文字直接放进 `Toggle` 的 label：macOS 上 `.switch` 样式在 Form 之外会把开关
    /// 紧贴着文字排布，不会自动靠右。所以拆成「可点击的文字 + 隐藏 label 的开关」。
    private var masterToggle: some View {
        HStack(spacing: WLSpacing.sm) {
            // 让整行文字区域也能点击切换；对辅助功能隐藏，由右侧开关本身朗读。
            Button {
                setEnabled(!settings.isEnabled)
            } label: {
                Text("启用自动锁定")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)

            Toggle("启用自动锁定", isOn: Binding(
                get: { settings.isEnabled },
                set: { setEnabled($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .help("关闭后不再自动锁定，菜单栏只显示状态")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wlCard(horizontal: WLSpacing.md, vertical: WLSpacing.sm)
    }

    private func setEnabled(_ value: Bool) {
        settings.isEnabled = value
        session.refreshConfig()
    }

    @ViewBuilder
    private var pauseRow: some View {
        if settings.isPaused {
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

    // MARK: - 主操作

    private var actions: some View {
        HStack(alignment: .center, spacing: WLSpacing.sm) {
            WLButton(
                "立即锁定",
                systemImage: "lock.fill",
                help: settings.confirmBeforeLock ? "锁定前会先确认" : "点按后立即锁定屏幕（⌃⌘Q）"
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
                WLButtonLabel("设置…", systemImage: "gearshape")
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
            WLButtonLabel("暂停", systemImage: "pause.fill")
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
                Text(rssi == -127 ? "模拟：信号丢失" : "模拟：\(rssi) dBm")
                    .font(WLFont.caption)
                    .foregroundStyle(WLColor.warning)
            }
        }
    }

    /// 用 `.plain` 按钮样式 + 自绘标签，去掉 `.borderlessButton` 自带的内边距，
    /// 让「更多」与卡片左边缘对齐。
    private var moreMenu: some View {
        Menu {
            if settings.debugMenuEnabled {
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
        .help("调试与退出")
    }
}
