import AppKit

/// 菜单栏状态图标。
///
/// 从应用 logo 提炼出「环形锁体 + 锁梁」：锁梁开 / 合表达手表在不在，
/// 其余状态靠锁体内的小标记区分。用代码绘制成模板图（`isTemplate = true`），
/// 不依赖位图资源，任意缩放都锐利，颜色由系统按菜单栏明暗自动着色。
///
/// 几何以 18×18 画布、y 轴向下为基准（与 `docs/ui-design/08-menubar-icons.html` 一致），
/// 绘制时统一翻转到 AppKit 的 y 轴向上坐标。
enum MenuBarIcon {
    /// 图标逻辑尺寸（pt）。
    static let size = NSSize(width: 18, height: 18)

    private static let lineWidth: CGFloat = 1.8
    private static let canvas: CGFloat = 18

    private static let bodyCenter = CGPoint(x: 9, y: 11.2)
    private static let bodyRadius: CGFloat = 5.1
    private static let shackleCenter = CGPoint(x: 9, y: 5.3)
    private static let shackleRadius: CGFloat = 3.7
    private static let shackleFootY: CGFloat = 8.2
    /// 开锁时锁梁左端在圆弧上的断点角度（以 y 向上、逆时针为正）。
    private static let openBreakAngle: CGFloat = 165
    /// 「已关闭」态的整体不透明度（模板图的 alpha 会被系统保留）。
    static let disabledAlpha: CGFloat = 0.42

    private static var cache: [ProximityStatus: NSImage] = [:]

    /// 状态对应的菜单栏图标（带缓存）。
    static func image(for status: ProximityStatus) -> NSImage {
        if let cached = cache[status] { return cached }
        let image = render(status)
        cache[status] = image
        return image
    }

    // MARK: - 绘制

    private static func render(_ status: ProximityStatus) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            switch status {
            case .near:
                strokeBody()
                strokeShackle(open: true)
            case .far:
                strokeBody()
                strokeShackle(open: false)
                fillDot(at: bodyCenter, radius: 1.4)
            case .unknown:
                strokeBody()
                strokeShackle(open: true)
                for dx: CGFloat in [-2.8, 0, 2.8] {
                    fillDot(at: CGPoint(x: bodyCenter.x + dx, y: bodyCenter.y), radius: 0.95)
                }
            case .paused:
                strokeBody()
                strokeShackle(open: true)
                strokeLine(from: CGPoint(x: 7.7, y: 9), to: CGPoint(x: 7.7, y: 13.4), width: 1.7)
                strokeLine(from: CGPoint(x: 10.3, y: 9), to: CGPoint(x: 10.3, y: 13.4), width: 1.7)
            case .disabled:
                // 整体变淡：用透明层统一降低 alpha，避免锁梁与锁体交叠处叠深。
                let cgContext = NSGraphicsContext.current?.cgContext
                cgContext?.setAlpha(disabledAlpha)
                cgContext?.beginTransparencyLayer(auxiliaryInfo: nil)
                strokeBody()
                strokeShackle(open: false)
                strokeLine(from: CGPoint(x: 6.9, y: 11.2), to: CGPoint(x: 11.1, y: 11.2), width: 1.7)
                cgContext?.endTransparencyLayer()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = status.title
        return image
    }

    /// 设计稿坐标（y 向下）→ AppKit 坐标（y 向上）。
    private static func flip(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: canvas - point.y)
    }

    private static func strokeBody() {
        let path = NSBezierPath(
            ovalIn: NSRect(
                x: bodyCenter.x - bodyRadius,
                y: canvas - bodyCenter.y - bodyRadius,
                width: bodyRadius * 2,
                height: bodyRadius * 2
            )
        )
        path.lineWidth = lineWidth
        path.stroke()
    }

    private static func strokeShackle(open: Bool) {
        let center = flip(shackleCenter)
        let footY = canvas - shackleFootY
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        if open {
            // 右腿接锁体，圆弧从右向左越过顶部，在 openBreakAngle 处断开。
            path.move(to: CGPoint(x: center.x + shackleRadius, y: footY))
            path.line(to: CGPoint(x: center.x + shackleRadius, y: center.y))
            path.appendArc(
                withCenter: center,
                radius: shackleRadius,
                startAngle: 0,
                endAngle: openBreakAngle,
                clockwise: false
            )
        } else {
            path.move(to: CGPoint(x: center.x - shackleRadius, y: footY))
            path.line(to: CGPoint(x: center.x - shackleRadius, y: center.y))
            path.appendArc(
                withCenter: center,
                radius: shackleRadius,
                startAngle: 180,
                endAngle: 0,
                clockwise: true
            )
            path.line(to: CGPoint(x: center.x + shackleRadius, y: footY))
        }
        path.stroke()
    }

    private static func strokeLine(from start: CGPoint, to end: CGPoint, width: CGFloat) {
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.move(to: flip(start))
        path.line(to: flip(end))
        path.stroke()
    }

    private static func fillDot(at point: CGPoint, radius: CGFloat) {
        let center = flip(point)
        NSBezierPath(
            ovalIn: NSRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        ).fill()
    }
}
