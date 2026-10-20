import SwiftUI

/// 距离刻度的分区。
///
/// 一律由 `SignalMeter.level` 推出，保证与信号条、判定引擎的口径一致：
/// 4 格 = 在身边（≥ 在身边阈值）；1 格 = 已离开（≤ 已离开阈值）；2~3 格 = 两者之间的过渡区。
enum ProximityZone: Equatable {
    case unknown
    case far
    case transition
    case near

    var title: String {
        switch self {
        case .unknown: return String(localized: "无信号")
        case .far: return String(localized: "已离开")
        case .transition: return String(localized: "过渡区")
        case .near: return String(localized: "在身边")
        }
    }
}

/// 距离刻度相关纯数学（可单测）。
enum ProximityGaugeMath {
    /// 当前信号落在哪个分区。RSSI ≥ 0（含 macOS 无有效信号时回传的 127）一律为 `.unknown`。
    static func zone(rssi: Double, nearRSSI: Int, farRSSI: Int) -> ProximityZone {
        switch SignalMeter.level(rssi: rssi, nearRSSI: nearRSSI, farRSSI: farRSSI) {
        case SignalMeter.levelCount: return .near
        case 2, 3: return .transition
        case 1: return .far
        default: return .unknown
        }
    }

    /// 指针在刻度上的 0...1 位置；信号无效时为 `nil`（不绘制指针）。
    /// 与设置里的 `ThresholdBand` 共用同一根轴（`ThresholdMath.bandRange`）。
    static func needleFraction(rssi: Double) -> CGFloat? {
        guard rssi < 0 else { return nil }
        return ThresholdMath.fraction(Int(rssi.rounded()))
    }

    /// 刻度各层的不透明度。
    ///
    /// 面板底在 macOS 26 上是系统 Liquid Glass 材质，背景会随壁纸 / 后方窗口变化；
    /// 半透明叠色在浅色壁纸上容易发白。用户开启「增强对比度」时整体加深一档，
    /// 依据：Apple《Adopting Liquid Glass》要求用不同显示 / 无障碍设置测试自定义元素与颜色，
    /// 并为自定义颜色提供增强对比度变体。具体数值为经验取值，待真机验证。
    struct Opacity: Equatable {
        /// 已离开 / 在身边分区（会自动锁定时）。
        let zone: Double
        /// 分区转灰时（暂停 / 已关闭 / 搜索中）。
        let idle: Double
        /// 中间过渡段与未填充底。
        let track: Double
    }

    static func opacity(increasedContrast: Bool) -> Opacity {
        increasedContrast
            ? Opacity(zone: 0.62, idle: 0.42, track: 0.24)
            : Opacity(zone: 0.38, idle: 0.26, track: 0.12)
    }
}

/// 距离刻度：一根只读的刻度条，回答「离自动锁定还有多远」。
///
/// 左端信号最弱、右端最强；按**当前阈值**切成「已离开 / 过渡 / 在身边」三段，指针是平滑后的 RSSI。
/// 阈值改了，分区位置立刻跟着动 —— 与 `SignalMeter`「按当前阈值分级」是同一个原则。
///
/// 它只是指示器，不是控件：指针是一条竖线而不是圆钮，避免被误认为可拖动的滑块。
struct ProximityGauge: View {
    let rssi: Double
    let nearRSSI: Int
    let farRSSI: Int
    /// 此刻是否会真正触发自动锁定。暂停 / 已关闭 / 搜索中为 `false`：
    /// 两侧分区转灰，避免用橙色暗示「马上要锁屏」。
    var isArmed = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private enum Metrics {
        static let trackHeight: CGFloat = 10
        static let needleWidth: CGFloat = 4
        static let needleHeight: CGFloat = 20
    }

    var body: some View {
        VStack(spacing: WLSpacing.xxs) {
            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                let farX = ThresholdMath.fraction(farRSSI) * width
                let nearX = ThresholdMath.fraction(nearRSSI) * width

                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        Rectangle().fill(farFill).frame(width: farX)
                        Rectangle().fill(Color.primary.opacity(opacity.track)).frame(width: max(nearX - farX, 0))
                        Rectangle().fill(nearFill)
                    }
                    .frame(height: Metrics.trackHeight)
                    .clipShape(Capsule(style: .continuous))

                    if let fraction = ProximityGaugeMath.needleFraction(rssi: rssi) {
                        let x = min(max(fraction * width - Metrics.needleWidth / 2, 0), width - Metrics.needleWidth)
                        Capsule(style: .continuous)
                            .fill(Color.primary)
                            .frame(width: Metrics.needleWidth, height: Metrics.needleHeight)
                            .offset(x: x)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: x)
                    }
                }
                .frame(width: width, height: Metrics.needleHeight, alignment: .leading)
            }
            .frame(height: Metrics.needleHeight)

            HStack {
                Text("已离开")
                Spacer(minLength: WLSpacing.sm)
                Text("在身边")
            }
            .font(WLFont.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("距离刻度")
        .accessibilityValue(ProximityGaugeMath.zone(rssi: rssi, nearRSSI: nearRSSI, farRSSI: farRSSI).title)
    }

    private var farFill: Color {
        isArmed ? WLColor.warning.opacity(opacity.zone) : WLColor.neutral.opacity(opacity.idle)
    }

    private var nearFill: Color {
        isArmed ? WLColor.success.opacity(opacity.zone) : WLColor.neutral.opacity(opacity.idle)
    }

    private var opacity: ProximityGaugeMath.Opacity {
        ProximityGaugeMath.opacity(increasedContrast: contrast == .increased)
    }
}
