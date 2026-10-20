import SwiftUI

/// 引导插画所处的阶段：同一幅「Mac — 信号 — 手表」线稿随步骤变化。
enum OnboardingArtStage: Equatable {
    /// 蓝牙尚未就绪：Mac 与手表之间是虚线，中间一枚蓝牙标记。
    case needsPermission
    /// 蓝牙就绪、正在找手表：信号波向手表扩散。
    case searching
    /// 已绑定并就绪：虚线贯通，手表角上一个对勾。
    case ready

    /// 步骤序号（0 授权 / 1 绑定 / 2 就绪）+ 蓝牙是否可用 → 阶段（纯函数，便于单测）。
    ///
    /// 第 1 步蓝牙已就绪时不再显示「连不上」，与状态卡的「蓝牙已就绪」保持一致。
    static func stage(forStep step: Int, bluetoothReady: Bool) -> OnboardingArtStage {
        switch step {
        case ..<1: return bluetoothReady ? .searching : .needsPermission
        case 1: return .searching
        default: return .ready
        }
    }
}

/// 引导窗口顶部的线稿插画：Mac — 信号 — 手表。
///
/// 只用强调色线条 + 窗口底色填充，跟随深浅色与系统强调色；纯装饰，对 VoiceOver 隐藏
/// （含义已由下方标题与状态卡表达）。依据 `docs/ui-design/.scratch/INDEX.md`「onboarding__spectrum」：
/// 选线稿档，避免实体渲染与系统线稿图标体系脱节。
struct OnboardingArt: View {
    let stage: OnboardingArtStage

    @Environment(\.colorScheme) private var colorScheme

    /// 画布设计尺寸（与设计稿 SVG viewBox 一致）。
    private static let canvas = CGSize(width: 360, height: 96)
    private static let lineWidth: CGFloat = 1.8

    var body: some View {
        Canvas { context, size in
            var ctx = context
            let scale = min(size.width / Self.canvas.width, size.height / Self.canvas.height)
            ctx.translateBy(
                x: (size.width - Self.canvas.width * scale) / 2,
                y: (size.height - Self.canvas.height * scale) / 2
            )
            ctx.scaleBy(x: scale, y: scale)
            draw(in: &ctx)
        }
        .aspectRatio(Self.canvas.width / Self.canvas.height, contentMode: .fit)
        .accessibilityHidden(true)
    }

    // MARK: 绘制

    private var line: Color { WLColor.accent }
    private var fill: Color { Color(nsColor: .windowBackgroundColor) }
    private var style: StrokeStyle {
        StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round, lineJoin: .round)
    }

    private func draw(in ctx: inout GraphicsContext) {
        drawMac(in: &ctx)
        switch stage {
        case .needsPermission: drawBluetoothLink(in: &ctx)
        case .searching: drawSignalWaves(in: &ctx)
        case .ready: drawReadyLink(in: &ctx)
        }
        drawWatch(in: &ctx)
        if stage == .ready { drawCheckBadge(in: &ctx) }
    }

    private func drawMac(in ctx: inout GraphicsContext) {
        let screen = Path(roundedRect: CGRect(x: 82, y: 26, width: 68, height: 44), cornerRadius: 5)
        ctx.fill(screen, with: .color(fill))
        ctx.stroke(screen, with: .color(line), style: style)
        var base = Path()
        base.move(to: CGPoint(x: 72, y: 76))
        base.addLine(to: CGPoint(x: 160, y: 76))
        ctx.stroke(base, with: .color(line), style: style)

        if stage == .ready {
            // 屏幕里的小锁：自动锁定已就绪。
            var inner = ctx
            inner.translateBy(x: 116, y: 48)
            inner.scaleBy(x: 1.25, y: 1.25)
            inner.translateBy(x: -8, y: -8)
            let body = Path(roundedRect: CGRect(x: 3.4, y: 7, width: 9.2, height: 7), cornerRadius: 2)
            var shackle = Path()
            shackle.move(to: CGPoint(x: 5.4, y: 7))
            shackle.addLine(to: CGPoint(x: 5.4, y: 5.2))
            shackle.addArc(center: CGPoint(x: 8, y: 5.2), radius: 2.6,
                           startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            shackle.addLine(to: CGPoint(x: 10.6, y: 7))
            let thin = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            inner.stroke(body, with: .color(line), style: thin)
            inner.stroke(shackle, with: .color(line), style: thin)
        }
    }

    private func drawWatch(in ctx: inout GraphicsContext) {
        var straps = Path()
        straps.move(to: CGPoint(x: 262, y: 34))
        straps.addLine(to: CGPoint(x: 262, y: 26))
        straps.addLine(to: CGPoint(x: 278, y: 26))
        straps.addLine(to: CGPoint(x: 278, y: 34))
        straps.move(to: CGPoint(x: 262, y: 70))
        straps.addLine(to: CGPoint(x: 262, y: 78))
        straps.addLine(to: CGPoint(x: 278, y: 78))
        straps.addLine(to: CGPoint(x: 278, y: 70))
        ctx.stroke(straps, with: .color(line), style: style)

        let body = Path(roundedRect: CGRect(x: 255, y: 34, width: 30, height: 36), cornerRadius: 10)
        ctx.fill(body, with: .color(fill))
        ctx.stroke(body, with: .color(line), style: style)

        var hands = Path()
        hands.move(to: CGPoint(x: 270, y: 46))
        hands.addLine(to: CGPoint(x: 270, y: 53))
        hands.addLine(to: CGPoint(x: 274, y: 56))
        ctx.stroke(hands, with: .color(line.opacity(0.7)),
                   style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
    }

    /// 蓝牙未就绪：虚线断开，中间一枚蓝牙标记。
    private func drawBluetoothLink(in ctx: inout GraphicsContext) {
        var dashes = Path()
        dashes.move(to: CGPoint(x: 152, y: 52)); dashes.addLine(to: CGPoint(x: 166, y: 52))
        dashes.move(to: CGPoint(x: 194, y: 52)); dashes.addLine(to: CGPoint(x: 250, y: 52))
        ctx.stroke(dashes, with: .color(line.opacity(0.5)),
                   style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [3, 5]))

        let badge = Path(ellipseIn: CGRect(x: 167, y: 39, width: 26, height: 26))
        ctx.fill(badge, with: .color(fill))
        ctx.stroke(badge, with: .color(line), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))

        // 蓝牙符文：竖线 + 两个折角。
        var rune = Path()
        let k: CGFloat = 0.9
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: 180 + x * k, y: 52 + y * k) }
        rune.move(to: p(0, -8)); rune.addLine(to: p(0, 8))
        rune.move(to: p(0, -8)); rune.addLine(to: p(5, -3.6)); rune.addLine(to: p(-5, 3.6))
        rune.move(to: p(0, 8)); rune.addLine(to: p(5, 3.6)); rune.addLine(to: p(-5, -3.6))
        ctx.stroke(rune, with: .color(line), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
    }

    /// 搜索中：三道信号波向手表扩散，手表外两圈光晕。
    private func drawSignalWaves(in ctx: inout GraphicsContext) {
        for (x, halfChord, radius, opacity) in [(176.0, 12.0, 16.0, 0.9), (190.0, 20.0, 28.0, 0.55), (204.0, 28.0, 40.0, 0.28)] {
            let centerX = x - (radius * radius - halfChord * halfChord).squareRoot()
            let half = asin(halfChord / radius)
            var wave = Path()
            wave.addArc(center: CGPoint(x: centerX, y: 52), radius: radius,
                        startAngle: .radians(-half), endAngle: .radians(half), clockwise: false)
            ctx.stroke(wave, with: .color(line.opacity(opacity)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        for (radius, opacity) in [(30.0, 0.25), (40.0, 0.12)] {
            let ring = Path(ellipseIn: CGRect(x: 270 - radius, y: 52 - radius, width: radius * 2, height: radius * 2))
            ctx.stroke(ring, with: .color(line.opacity(opacity)), lineWidth: 1)
        }
    }

    /// 已就绪：点线贯通 Mac 与手表。
    private func drawReadyLink(in ctx: inout GraphicsContext) {
        var dots = Path()
        dots.move(to: CGPoint(x: 160, y: 52))
        dots.addLine(to: CGPoint(x: 246, y: 52))
        ctx.stroke(dots, with: .color(line.opacity(0.35)),
                   style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [2, 6]))
    }

    private func drawCheckBadge(in ctx: inout GraphicsContext) {
        let badge = Path(ellipseIn: CGRect(x: 279, y: 25, width: 18, height: 18))
        ctx.fill(badge, with: .color(WLColor.success))
        var tick = Path()
        tick.move(to: CGPoint(x: 284, y: 34.4))
        tick.addLine(to: CGPoint(x: 286.8, y: 37.2))
        tick.addLine(to: CGPoint(x: 292, y: 31.4))
        ctx.stroke(tick, with: .color(.white),
                   style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
    }
}
