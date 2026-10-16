import SwiftUI

/// 候选设备行：图标 + 名称 + 命中依据 + 信号条 + 操作。
struct DeviceRow: View {
    let device: DiscoveredWatch
    let nearRSSI: Int
    let farRSSI: Int
    /// 已绑定该设备时禁用操作按钮。
    var isBound = false
    var actionTitle: String = "绑定"
    var actionHelp: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: WLSpacing.md) {
            Image(systemName: "applewatch")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: WLSpacing.xxs) {
                Text(displayName)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: WLSpacing.sm)

            SignalMeter(rssi: Double(device.rssi), nearRSSI: nearRSSI, farRSSI: farRSSI)
            Text(rssiText)
                .font(.caption.monospacedDigit())
                .frame(minWidth: 62, alignment: .trailing)

            Button(actionTitle) { action() }
                .disabled(isBound)
                .help(actionHelp ?? "")
        }
        .padding(.vertical, WLSpacing.xxs)
    }

    private var displayName: String {
        device.name.isEmpty
            ? "\(device.displayName) · \(device.id.uuidString.prefix(8))"
            : device.displayName
    }

    private var subtitle: String {
        device.matchReasons.isEmpty
            ? "未命中识别规则（可拿远 / 靠近观察信号变化辨认）"
            : device.matchReasons.sorted().joined(separator: " · ")
    }

    private var rssiText: String {
        device.rssi >= 0 ? "信号未知" : "\(device.rssi) dBm"
    }
}

/// 扫描状态行：让「列表为空」能自解释（蓝牙状态 / 是否在扫描 / 广播数）。
struct ScannerStatusBar: View {
    let isScanning: Bool
    let bluetoothTitle: String
    let deviceCount: Int
    let discoveryCount: Int
    var invalidRSSICount: Int = 0
    var message: String?

    var body: some View {
        HStack(spacing: WLSpacing.xs) {
            Text(isScanning ? "扫描中" : "未扫描")
            separator
            Text("蓝牙：\(bluetoothTitle)")
            separator
            Text("记录 \(deviceCount) 台")
            if discoveryCount > 0 {
                separator
                Text("已收到 \(discoveryCount) 条广播")
                if invalidRSSICount > 0 {
                    Text("（\(invalidRSSICount) 条无有效信号强度）")
                        .foregroundStyle(WLColor.warning)
                }
            }
            if let message {
                separator
                Text(message).foregroundStyle(WLColor.danger)
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private var separator: some View {
        Text("·").foregroundStyle(.tertiary)
    }
}
