import SwiftUI

/// 辅助设备卡片：让 iPhone / AirPods 等在「手表信号丢失」时帮忙判断人是否还在附近。
///
/// 语义与上限见 `PresenceFusion`。界面上必须讲清楚两件事，避免用户高估它：
/// 1. 只会**延缓**由「信号丢失」触发的锁定，不会主动锁屏，也推翻不了「手表信号明确很弱」；
/// 2. 有硬上限，且 iPhone 息屏后可能不再广播，所以并不保证有效。
struct AuxiliaryDevicesCard: View {
    @EnvironmentObject private var session: AppSession
    @ObservedObject private var settings = SettingsStore.shared

    /// 周期刷新，让「在附近」「信号」读数保持新鲜（候选列表本身由 `AppSession` 每秒刷新并保持稳定）。
    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    @State private var refreshToken = 0

    private var candidates: [DiscoveredWatch] { session.auxiliaryCandidates }

    var body: some View {
        VStack(alignment: .leading, spacing: WLSpacing.sm) {
            CardSectionHeader(title: String(localized: "辅助设备"), systemImage: "iphone", tint: Color.primary)

            Toggle("手表信号丢失时，参考辅助设备", isOn: $settings.fusionEnabled)
                .help("手表偶尔收不到广播但你其实还在时，附近有你选的设备就先不锁屏")

            Text(explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            selected
            if settings.auxiliaryDevices.count < PresenceFusion.maxDevices {
                CardDivider()
                available
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wlCard()
        .onReceive(tick) { _ in refreshToken &+= 1 }
    }

    private var explanation: String {
        String(localized: "辅助设备只会推迟「手表信号丢失」引起的锁定，最多 \(Int(PresenceFusion.Config().maxHold / 60)) 分钟；它不会让 Mac 自己锁屏，手表信号明确很弱时也不会被它推翻。iPhone 息屏后可能不再广播，效果取决于设备状态。")
    }

    // MARK: - 已选择

    @ViewBuilder
    private var selected: some View {
        if settings.auxiliaryDevices.isEmpty {
            Text("还没有选择辅助设备。")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: WLSpacing.xs) {
                ForEach(Array(settings.auxiliaryDevices.enumerated()), id: \.element.id) { index, device in
                    let label = session.label(forAuxiliary: device)
                    HStack(spacing: WLSpacing.md) {
                        Image(systemName: label.kind.symbolName)
                            .frame(width: 20)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: WLSpacing.xxs) {
                            Text(label.name)
                            Text(status(of: device))
                                .font(.caption)
                                .foregroundStyle(session.isAuxiliaryNear(id: device.id) ? WLColor.success : Color.secondary)
                        }
                        Spacer(minLength: WLSpacing.sm)
                        DeviceEditButton(deviceID: device.id, currentName: label.name)
                        WLButton(String(localized: "移除"), systemImage: "minus.circle") {
                            session.removeAuxiliaryDevice(id: device.id)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .help("不再参考这台设备")
                    }
                    if index < settings.auxiliaryDevices.count - 1 { Divider() }
                }
            }
        }
    }

    private func status(of device: AuxiliaryDevice) -> String {
        _ = refreshToken
        guard let rssi = session.auxiliaryRSSI(id: device.id) else {
            return device.name.isEmpty
                ? String(localized: "近期没有收到广播（未命名设备的地址轮换后无法续接）")
                : String(localized: "近期没有收到广播")
        }
        return session.isAuxiliaryNear(id: device.id)
            ? String(localized: "在附近 · \(rssi) dBm")
            : String(localized: "较远 · \(rssi) dBm")
    }

    // MARK: - 可添加

    @ViewBuilder
    private var available: some View {
        VStack(alignment: .leading, spacing: WLSpacing.sm) {
            Text("附近可添加的设备")
                .font(.caption)
                .foregroundStyle(.secondary)
            if candidates.isEmpty {
                Text("暂时没有发现设备。把 iPhone 亮屏放在旁边，或戴上 AirPods 后再看。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                DeviceGrid {
                    ForEach(candidates) { device in
                        DeviceTile(
                            deviceID: device.id.uuidString,
                            label: session.label(for: device),
                            signal: .init(rssi: device.rssi, nearRSSI: settings.nearRSSI, farRSSI: settings.farRSSI),
                            badge: .add,
                            help: DeviceTile.help(
                                String(localized: "点击添加为辅助设备；有名称的设备地址轮换后可以自动续接"),
                                for: device
                            )
                        ) {
                            session.addAuxiliaryDevice(device)
                        }
                    }
                }
            }
            Text("靠名称辨认：同一台 iPhone 与手表的广播类型相同，无法自动区分，请只添加你认得的设备。最多 \(PresenceFusion.maxDevices) 台。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
