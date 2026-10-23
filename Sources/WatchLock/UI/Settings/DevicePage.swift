import SwiftUI

/// 设备页：绑定 / 解除绑定 / 候选设备列表。
struct DevicePage: View {
    @EnvironmentObject private var session: AppSession
    @ObservedObject private var settings = SettingsStore.shared

    @State private var confirmingUnbind = false

    private var candidates: [DiscoveredWatch] { session.bindingCandidates }

    var body: some View {
        SettingsDetail {
            VStack(alignment: .leading, spacing: WLSpacing.md) {
                boundCard
                candidateCard
                AuxiliaryDevicesCard()
                ScannerStatusBar(
                    isScanning: session.scanner.isScanning,
                    bluetoothTitle: session.bluetoothState.title,
                    message: session.scannerMessage
                )

                Text("把手表贴近 Mac，最靠前的那台通常就是它。名称不是必需条件，绑定后按设备标识追踪。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 候选设备

    private var candidateCard: some View {
        VStack(alignment: .leading, spacing: WLSpacing.sm) {
            HStack(spacing: WLSpacing.sm) {
                CardSectionHeader(
                    title: String(localized: "附近设备"),
                    systemImage: "wave.3.right",
                    tint: Color.primary
                )
                Spacer(minLength: WLSpacing.sm)
                // 贴合内容宽度：WLButton 默认会撑满剩余空间，放在标题行里会变成一条长按钮。
                WLButton(String(localized: "重新扫描"), systemImage: "arrow.clockwise") { session.rescan() }
                    .fixedSize(horizontal: true, vertical: false)
                    .help("重启蓝牙扫描，用于列表长时间为空时")
            }
            Text("点击设备即可绑定。靠近 Mac 的排在前面，最靠前的那台通常就是你的手表。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            list
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wlCard()
    }

    // MARK: - 已绑定

    private var boundCard: some View {
        let boundLabel = session.boundDeviceLabel()
        return HStack(spacing: WLSpacing.md) {
            Image(systemName: boundLabel?.kind.symbolName ?? DeviceKind.watch.symbolName)
                .font(.system(size: 20))
                .foregroundStyle(settings.boundWatchID == nil ? Color.secondary : WLColor.success)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: WLSpacing.xxs) {
                // 未绑定时不能写「已绑定」：标签与内容会互相矛盾。已绑定但没有名称时也不能写「尚未绑定」。
                Text(settings.boundWatchID == nil ? String(localized: "未绑定") : String(localized: "已绑定"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(boundLabel?.name ?? String(localized: "在下方列表中选择你的手表"))
            }
            Spacer(minLength: WLSpacing.sm)
            if let boundID = settings.boundWatchID {
                DeviceEditButton(deviceID: boundID, currentName: boundLabel?.name ?? "")
                WLButton(String(localized: "解除绑定"), systemImage: "trash", role: .danger) {
                    confirmingUnbind = true
                }
                .fixedSize(horizontal: true, vertical: false)
                .help("解除后需要重新绑定才会继续自动锁定")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wlCard()
        .confirmationDialog("解除与「\(boundLabel?.name ?? String(localized: "该设备"))」的绑定？", isPresented: $confirmingUnbind) {
            Button("解除绑定", role: .destructive) { session.unbindWatch() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("解除后自动锁定会停止，需要重新绑定。")
        }
    }

    // MARK: - 候选列表

    @ViewBuilder
    private var list: some View {
        if candidates.isEmpty {
            EmptyStateView(
                title: String(localized: "暂未发现候选设备"),
                systemImage: "wave.3.right",
                message: emptyHint
            )
        } else {
            DeviceGrid {
                ForEach(candidates) { device in
                    let isBound = settings.boundWatchID == device.id.uuidString
                    let label = session.label(for: device)
                    DeviceTile(
                        deviceID: device.id.uuidString,
                        label: label,
                        signal: .init(rssi: device.rssi, nearRSSI: settings.nearRSSI, farRSSI: settings.farRSSI),
                        badge: isBound ? .selected : nil,
                        help: DeviceTile.help(
                            isBound
                                ? String(localized: "已绑定")
                                : String(localized: "点击绑定。绑定后按设备标识追踪，广播地址轮换时会自动续接"),
                            for: device
                        ),
                        confirmation: .bind(
                            deviceName: label.name,
                            replacing: session.boundDeviceLabel()?.name
                        )
                    ) {
                        session.bind(watch: device)
                    }
                }
            }
        }
    }

    /// 让「空列表」自解释，避免用户不知道下一步该做什么。
    private var emptyHint: String {
        if session.bluetoothState != .poweredOn {
            return String(localized: "蓝牙未就绪（\(session.bluetoothState.title)）。若刚重新打包安装，macOS 可能按新应用重新要求蓝牙权限：系统设置 → 隐私与安全性 → 蓝牙。")
        }
        if !session.scanner.isScanning {
            return String(localized: "当前未在扫描。请确认「通用」里自动锁定已开启且未暂停。")
        }
        if session.scanner.discoveryCount == 0 {
            return String(localized: "暂未发现任何 BLE 广播。请确认手表在旁边、已解锁且蓝牙开启。")
        }
        return String(localized: "附近有蓝牙设备，但暂时没有识别到可绑定的手表。请让手表靠近 Mac 并保持解锁。")
    }
}
