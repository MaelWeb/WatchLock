import AppKit
import SwiftUI

/// 诊断页：误锁调参 + 诊断日志 + 广播抓包 + 调试开关（原「高级」后半部分）。
///
/// 整页是单个 `VStack`：日志区独占剩余高度，不再出现「外层滚动套内层滚动」。
struct DiagnosticsPage: View {
    @EnvironmentObject private var session: AppSession
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var log = DiagnosticsLog.shared

    @State private var confirmingClearLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: WLSpacing.md) {
            tuningCard
            logCard
            // 广播抓包与调试说明只给开发 / 排查用，普通用户不可见（见 `DeveloperMode`）。
            if DeveloperMode.isEnabled {
                captureCard
                debugCard
            }
        }
        .padding(WLSpacing.lg)
        .frame(minWidth: 460, maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - 误锁反馈与自动调参

    private var tuningCard: some View {
        FormCard(
            title: String(localized: "误锁反馈与自动调参"),
            subtitle: String(localized: "在菜单栏点击「刚才这次是误锁？」即记为一次误锁；误锁率超过 20%（至少 3 次样本）时自动放宽「已离开」阈值，长期无误锁后缓慢回到默认值。")
        ) {
            HStack(spacing: WLSpacing.sm) {
                StatChip(label: String(localized: "自动锁定"), value: "\(settings.autoLockCount)")
                StatChip(
                    label: String(localized: "误锁"),
                    value: "\(settings.falseLockCount)",
                    tint: settings.falseLockCount > 0 ? WLColor.warning : Color.primary
                )
                StatChip(
                    label: String(localized: "误锁率"),
                    value: "\(Int(AutoTuner.falseLockRate(settings.tuningFeedback) * 100))%"
                )
            }
            if let message = session.tuningMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: WLSpacing.sm) {
                WLButton(String(localized: "恢复默认阈值"), width: 130) { session.resetTuning() }
                    .help("清空自动调参样本并把阈值恢复到默认")
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - 诊断日志

    private var logCard: some View {
        FormCard(title: String(localized: "诊断日志")) {
            if log.entries.isEmpty {
                EmptyStateView(
                    title: String(localized: "暂无日志"),
                    systemImage: "doc.text",
                    message: String(localized: "应用运行后会自动记录扫描、锁定与校准事件。")
                )
                .frame(minHeight: 140)
            } else {
                // 固定高度的单一滚动区：不用 List，避免卡片里出现列表行缩进与分隔线。
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: WLSpacing.xs) {
                        ForEach(log.entries.reversed()) { entry in
                            VStack(alignment: .leading, spacing: WLSpacing.xxs) {
                                Text("\(entry.date.formatted(date: .omitted, time: .standard)) · \(entry.level.title)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(entry.message)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 140, maxHeight: .infinity)
                .wlCard(tint: .plain, padding: WLSpacing.sm)
            }

            HStack(spacing: WLSpacing.sm) {
                WLButton(String(localized: "导出…"), width: 100) { exportLog() }
                WLButton(String(localized: "清空日志"), role: .danger, width: 100) { confirmingClearLog = true }
                Spacer(minLength: 0)
            }
        }
        .confirmationDialog("清空全部诊断日志？", isPresented: $confirmingClearLog) {
            Button("清空", role: .destructive) { log.clear() }
            Button("取消", role: .cancel) {}
        }
    }

    private func exportLog() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "watchlock-log.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? log.exportText().write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - 广播抓包

    private var captureCard: some View {
        DisclosureGroup {
            AdvertisementCaptureSection()
                .padding(.top, WLSpacing.sm)
        } label: {
            CardSectionHeader(
                title: String(localized: "广播抓包（用于固化识别规则）"),
                systemImage: "antenna.radiowaves.left.and.right",
                tint: Color.primary
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wlCard()
        .help("展开后可复制候选设备的广播内容，用于排查识别问题")
    }

    // MARK: - 调试

    private var debugCard: some View {
        FormCard(title: String(localized: "调试")) {
            Text("开发者模式已开启：菜单栏「更多」里有模拟信号子菜单，可注入 -50 / -65 / -85 dBm 或模拟信号丢失，不必真的走动就能验证锁定链路。也可以带环境变量启动：WATCHLOCK_FAKE_RSSI=-85")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let path = DiagnosticsLog.fileURL?.path {
                Text("日志文件：\(path)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

// MARK: - 广播抓包

/// 展示候选设备广播里的厂商数据，便于真机抓包后固化识别规则（认广播类型，而非猜名字）。
private struct AdvertisementCaptureSection: View {
    @EnvironmentObject private var session: AppSession
    @State private var captureText = ""
    @State private var copied = false

    /// 直接读扫描结果（不缓存）：housekeeping 每秒刷新 session 的 @Published 属性，
    /// 视图随之重算，数据永远是最新的。
    private var devices: [DiscoveredWatch] { session.allDiscoveredDevices() }

    var body: some View {
        VStack(alignment: .leading, spacing: WLSpacing.sm) {
            Text("让手表保持在旁边，把这里的内容复制出来即可用于固化识别规则。类型字节的语义需真机数据确认，当前只解析结构。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScannerStatusBar(
                isScanning: session.scanner.isScanning,
                bluetoothTitle: session.bluetoothState.title,
                message: session.scannerMessage
            )

            if devices.isEmpty {
                Text(emptyHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(devices.prefix(8))) { device in
                    VStack(alignment: .leading, spacing: WLSpacing.xxs) {
                        Text("\(device.displayName) · \(rssiText(device))")
                            .font(.caption)
                        Text(AppleAdvertisement.describe(device.manufacturerData)
                             ?? String(localized: "无厂商数据 / 非 Apple 广播"))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            HStack(spacing: WLSpacing.sm) {
                WLButton(String(localized: "复制抓包信息"), width: 130) { copy() }
                WLButton(String(localized: "导出…"), width: 100) { export() }
                if copied {
                    Text("已复制到剪贴板")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var emptyHint: String {
        if session.bluetoothState != .poweredOn {
            return String(localized: "蓝牙未就绪（\(session.bluetoothState.title)）。若刚重新打包安装，macOS 可能按新应用重新要求蓝牙权限：系统设置 → 隐私与安全性 → 蓝牙。")
        }
        if !session.scanner.isScanning {
            return String(localized: "当前未在扫描。请确认「通用」里自动锁定已开启且未暂停。")
        }
        if session.scanner.discoveryCount == 0 {
            return String(localized: "暂未发现任何 BLE 广播。请确认手表在旁边且蓝牙开启。")
        }
        if devices.isEmpty {
            return String(localized: "暂未记录到设备。请确认手表在旁边且蓝牙开启。")
        }
        return String(localized: "系统暂未提供有效的信号强度，可尝试关闭再打开 Mac 蓝牙。")
    }

    private func rssiText(_ device: DiscoveredWatch) -> String {
        device.rssi >= 0 ? String(localized: "信号强度未知") : "\(device.rssi) dBm"
    }

    private func makeText() -> String {
        devices.prefix(8).map { device -> String in
            let manu = AppleAdvertisement.hex(device.manufacturerData) ?? "-"
            let parsed = AppleAdvertisement.describe(device.manufacturerData) ?? "-"
            return "\(device.displayName)\trssi=\(rssiText(device))\tmanu=\(manu)\t\(parsed)"
        }
        .joined(separator: "\n")
    }

    private func copy() {
        captureText = makeText()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(captureText, forType: .string)
        copied = !captureText.isEmpty
    }

    private func export() {
        captureText = makeText()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "watchlock-capture.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? captureText.write(to: url, atomically: true, encoding: .utf8)
    }
}
