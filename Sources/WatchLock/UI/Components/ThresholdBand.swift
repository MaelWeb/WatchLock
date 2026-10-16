import SwiftUI

/// 阈值相关纯数学（可单测）。
enum ThresholdMath {
    static let nearRange = -90 ... -35
    static let farRange = -100 ... -50
    /// 刻度带整体范围：左端最弱、右端最强。
    static let bandRange = -100 ... -35
    /// 「在身边」与「已离开」之间强制保留的最小间隔（dBm）。
    static let minimumGap = 5

    /// 把两个阈值收敛到合法组合：各自落在量程内，且 `near − far ≥ minimumGap`。
    static func clamp(near: Int, far: Int) -> (near: Int, far: Int) {
        var n = min(max(near, nearRange.lowerBound), nearRange.upperBound)
        var f = min(max(far, farRange.lowerBound), farRange.upperBound)

        if n - f < minimumGap {
            // 优先压缩「已离开」；触到量程下限时再回头抬高「在身边」。
            f = max(min(f, n - minimumGap), farRange.lowerBound)
            n = min(max(n, f + minimumGap), nearRange.upperBound)
            if n - f < minimumGap {
                f = n - minimumGap
            }
        }
        return (n, f)
    }

    /// dBm → 刻度带上的 0...1 位置。
    static func fraction(_ value: Int) -> CGFloat {
        let lower = Double(bandRange.lowerBound)
        let upper = Double(bandRange.upperBound)
        guard upper > lower else { return 0 }
        let clamped = min(max(Double(value), lower), upper)
        return CGFloat((clamped - lower) / (upper - lower))
    }

    /// 刻度带位置 → dBm。
    static func value(fraction: CGFloat) -> Int {
        let lower = Double(bandRange.lowerBound)
        let upper = Double(bandRange.upperBound)
        let ratio = Double(min(max(fraction, 0), 1))
        return Int((lower + ratio * (upper - lower)).rounded())
    }
}

/// 同轴阈值带：一根刻度条上同时呈现「已离开 / 在身边 / 当前信号」。
///
/// 替换原来的两个独立 Slider —— 能直接看出两个阈值的相对关系，且拖动时经
/// `ThresholdMath.clamp` 强制保留最小间隔，设不出非法组合。
struct ThresholdBand: View {
    @Binding var nearRSSI: Int
    @Binding var farRSSI: Int
    /// 当前实时信号（dBm）；≥ 0 表示无有效信号，不绘制指针。
    var currentRSSI: Double = 0

    @State private var activeHandle: Handle?

    private enum Handle {
        case near
        case far
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WLSpacing.sm) {
            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                let nearX = ThresholdMath.fraction(nearRSSI) * width
                let farX = ThresholdMath.fraction(farRSSI) * width

                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(WLColor.track)
                        .frame(height: 6)
                    Capsule(style: .continuous)
                        .fill(WLColor.success.opacity(0.4))
                        .frame(width: max(nearX - farX, 0), height: 6)
                        .offset(x: farX)
                    if currentRSSI < 0 {
                        Capsule(style: .continuous)
                            .fill(WLColor.accent)
                            .frame(width: 2, height: 24)
                            .offset(x: currentX * width)
                    }
                    handle(color: WLColor.warning, x: farX, help: "已离开阈值，拖到刚走出判定范围的位置")
                    handle(color: WLColor.success, x: nearX, help: "在身边阈值，拖到日常办公时的信号强度")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(dragGesture(width: width))
            }
            .frame(height: 34)

            legend
        }
        .accessibilityElement()
        .accessibilityLabel("距离阈值")
        .accessibilityValue("在身边 \(nearRSSI) dBm，已离开 \(farRSSI) dBm，间隔 \(nearRSSI - farRSSI) dBm")
    }

    private var currentX: CGFloat {
        ThresholdMath.fraction(Int(currentRSSI.rounded()))
    }

    private var gap: Int { nearRSSI - farRSSI }

    // MARK: 图例

    private var legend: some View {
        HStack(spacing: WLSpacing.sm) {
            legendDot(WLColor.success)
            Text("在身边 \(nearRSSI) dBm").monospacedDigit()
            legendDot(WLColor.warning)
            Text("已离开 \(farRSSI) dBm").monospacedDigit()
            Spacer(minLength: WLSpacing.sm)
            Text("间隔 \(gap) dBm")
                .monospacedDigit()
                .foregroundStyle(gap >= ThresholdMath.minimumGap ? Color.secondary : WLColor.warning)
        }
        .font(.caption)
    }

    private func legendDot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }

    private func handle(color: Color, x: CGFloat, help: String) -> some View {
        Circle()
            .fill(color)
            .frame(width: 14, height: 14)
            .overlay {
                Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5)
            }
            .offset(x: x - 7)
            .help(help)
            .accessibilityHidden(true)
    }

    // MARK: 拖拽

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if activeHandle == nil {
                    activeHandle = nearestHandle(x: value.location.x, width: width)
                }
                guard let activeHandle else { return }
                apply(activeHandle, ThresholdMath.value(fraction: value.location.x / width))
            }
            .onEnded { _ in activeHandle = nil }
    }

    private func nearestHandle(x: CGFloat, width: CGFloat) -> Handle {
        let nearX = ThresholdMath.fraction(nearRSSI) * width
        let farX = ThresholdMath.fraction(farRSSI) * width
        return abs(x - nearX) <= abs(x - farX) ? .near : .far
    }

    private func apply(_ handle: Handle, _ value: Int) {
        let clamped: (near: Int, far: Int)
        switch handle {
        case .near:
            clamped = ThresholdMath.clamp(near: value, far: farRSSI)
        case .far:
            clamped = ThresholdMath.clamp(near: nearRSSI, far: value)
        }
        nearRSSI = clamped.near
        farRSSI = clamped.far
    }
}
