import SwiftUI

/// 一个指标读数：数字 + 可选单位（单位用小字，不与数字抢视觉）。
struct MetricReading: Equatable {
    let value: String
    let unit: String?

    /// 朗读 / 复制用的完整文案，如「−48 dBm」；没有读数时只有占位符。
    var spoken: String {
        guard let unit else { return value }
        return "\(value) \(unit)"
    }

    /// 没有有效读数时的占位。
    static let none = MetricReading(value: "—", unit: nil)
}

/// 菜单栏指标瓦片的读数换算（纯函数，便于单测）。
enum MenuBarMetrics {
    /// 信号强度。RSSI ≥ 0（含 macOS 无有效信号时回传的 127）一律视为没有读数。
    static func signal(rssi: Double) -> MetricReading {
        guard rssi < 0 else { return .none }
        return MetricReading(value: String(format: "%.0f", rssi), unit: String(localized: "dBm"))
    }

    /// 估算距离（米）。≤ 0 表示未知。
    static func distance(meters: Double) -> MetricReading {
        guard meters > 0 else { return .none }
        return MetricReading(value: String(format: "%.1f", meters), unit: String(localized: "米"))
    }

    /// 距上次收到信号过去多久：不足 1 分钟按秒，之后按整分钟向下取整。
    /// 时钟回拨导致负数时按 0 处理。
    static func updated(since date: Date?, now: Date = Date()) -> MetricReading {
        guard let date else { return .none }
        let seconds = max(Int(now.timeIntervalSince(date)), 0)
        if seconds < 60 {
            return MetricReading(value: "\(seconds)", unit: String(localized: "秒前"))
        }
        return MetricReading(value: "\(seconds / 60)", unit: String(localized: "分钟前"))
    }
}

/// 指标瓦片：小标签 + 大数字，三块并排放在菜单栏面板里。
///
/// 数字是主角（17 semibold、等宽数字），单位缩成 11 的次要色小字；
/// 标签行右侧可放一个小附件（如信号条）。
struct MetricTile<Accessory: View>: View {
    let title: String
    let reading: MetricReading
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: WLSpacing.xxs) {
            HStack(spacing: WLSpacing.xs) {
                Text(title)
                    .font(WLFont.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                accessory
            }
            .frame(minHeight: 15)

            HStack(alignment: .firstTextBaseline, spacing: WLSpacing.xxs) {
                Text(reading.value)
                    .font(WLFont.metric.monospacedDigit())
                if let unit = reading.unit {
                    Text(unit)
                        .font(WLFont.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wlCard(horizontal: WLSpacing.md, vertical: WLSpacing.sm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(reading.spoken)
    }
}

extension MetricTile where Accessory == EmptyView {
    init(title: String, reading: MetricReading) {
        self.init(title: title, reading: reading) { EmptyView() }
    }
}
