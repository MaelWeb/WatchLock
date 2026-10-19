import SwiftUI

/// 4 格信号条。
///
/// 分级按**当前阈值**动态计算，而不是固定 dBm 分段 —— 保证「看到的格数」与
/// 「会不会锁屏」永远一致，用户调完阈值后能立刻验证（设计稿 §3）。
struct SignalMeter: View {
    let rssi: Double
    let nearRSSI: Int
    let farRSSI: Int

    static let levelCount = 4

    var body: some View {
        HStack(alignment: .bottom, spacing: WLSpacing.xxs) {
            ForEach(0 ..< Self.levelCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(index < level ? fillColor : WLColor.track)
                    .frame(width: 4, height: barHeight(index))
            }
        }
        .frame(width: 22, height: 15, alignment: .bottom)
        .accessibilityElement()
        .accessibilityLabel("信号强度")
        .accessibilityValue(accessibilityValue)
    }

    private var level: Int {
        Self.level(rssi: rssi, nearRSSI: nearRSSI, farRSSI: farRSSI)
    }

    private var fillColor: Color {
        switch level {
        case 3, 4: return WLColor.success
        case 1, 2: return WLColor.warning
        default: return WLColor.neutral
        }
    }

    private var accessibilityValue: String {
        guard level > 0 else { return String(localized: "无信号") }
        return String(localized: "\(level) 格，共 \(Self.levelCount) 格")
    }

    private func barHeight(_ index: Int) -> CGFloat {
        4 + CGFloat(index) * 3.6
    }

    /// 信号分级（纯函数，便于单测）。
    ///
    /// - RSSI ≥ 0 视为无效值（macOS 在拿不到信号强度时会回传 127）。
    /// - ≥ 在身边阈值 → 4 格；两者之间按中点分 3 / 2 格；≤ 已离开阈值 → 1 格。
    static func level(rssi: Double, nearRSSI: Int, farRSSI: Int) -> Int {
        guard rssi < 0 else { return 0 }
        let near = Double(nearRSSI)
        let far = Double(farRSSI)
        if rssi >= near { return Self.levelCount }
        if rssi >= (near + far) / 2 { return 3 }
        if rssi > far { return 2 }
        return 1
    }
}
