import SwiftUI

/// 扫描状态行：让「列表为空」能自解释（蓝牙状态 / 是否在扫描）。
struct ScannerStatusBar: View {
    let isScanning: Bool
    let bluetoothTitle: String
    var message: String?

    var body: some View {
        HStack(spacing: WLSpacing.xs) {
            Text(isScanning ? String(localized: "扫描中") : String(localized: "未扫描"))
            separator
            Text("蓝牙：\(bluetoothTitle)")
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
