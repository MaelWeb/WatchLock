import AppKit
import XCTest
@testable import WatchLock

/// 菜单栏状态图标：必须是模板图、尺寸正确、五态互不相同，且「已关闭」整体偏淡。
final class MenuBarIconTests: XCTestCase {

    /// 把图标栅格化到固定 36×36 像素（2x），便于逐像素比较。
    private func bitmap(for status: ProximityStatus) -> NSBitmapImageRep? {
        let image = MenuBarIcon.image(for: status)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 36,
            pixelsHigh: 36,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: 36, height: 36))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// 按「行 × 列」展开 alpha 通道；`bytesPerRow` 可能带对齐填充，不能直接按 36 一行换算。
    private func alphaValues(_ rep: NSBitmapImageRep) -> [UInt8] {
        guard let data = rep.bitmapData else { return [] }
        var result: [UInt8] = []
        result.reserveCapacity(rep.pixelsWide * rep.pixelsHigh)
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                result.append(data[y * rep.bytesPerRow + x * rep.samplesPerPixel + 3])
            }
        }
        return result
    }

    func testEveryStatusIsTemplateImageWithExpectedSize() {
        for status in ProximityStatus.allCases {
            let image = MenuBarIcon.image(for: status)
            XCTAssertTrue(image.isTemplate, "\(status) 必须是模板图，才能适配深浅色菜单栏")
            XCTAssertEqual(image.size, MenuBarIcon.size)
        }
    }

    func testImageIsCachedPerStatus() {
        XCTAssertTrue(MenuBarIcon.image(for: .near) === MenuBarIcon.image(for: .near))
    }

    func testEveryStatusDrawsSomething() throws {
        for status in ProximityStatus.allCases {
            let rep = try XCTUnwrap(bitmap(for: status))
            XCTAssertTrue(alphaValues(rep).contains { $0 > 0 }, "\(status) 绘制结果为空")
        }
    }

    func testStatusIconsAreVisuallyDistinct() throws {
        var seen: [[UInt8]: ProximityStatus] = [:]
        for status in ProximityStatus.allCases {
            let rep = try XCTUnwrap(bitmap(for: status))
            let pixels = alphaValues(rep)
            if let other = seen[pixels] {
                XCTFail("\(status) 与 \(other) 的图标完全相同")
            }
            seen[pixels] = status
        }
    }

    func testDisabledIsFainterThanClosedLock() throws {
        let disabled = try XCTUnwrap(bitmap(for: .disabled))
        let peak = alphaValues(disabled).max() ?? 0
        // 峰值 alpha 不应超过 disabledAlpha（留 8% 容差给抗锯齿与取整）。
        XCTAssertLessThanOrEqual(Double(peak) / 255, Double(MenuBarIcon.disabledAlpha) + 0.08)
        XCTAssertGreaterThan(peak, 0)
    }

    func testIconStaysInsideCanvas() throws {
        // 画布四周 1 个像素（2x 下 0.5pt）不应有笔画，防止被菜单栏裁切。
        for status in ProximityStatus.allCases {
            let rep = try XCTUnwrap(bitmap(for: status))
            let alpha = alphaValues(rep)
            for index in 0..<alpha.count {
                let x = index % 36
                let y = index / 36
                guard x == 0 || y == 0 || x == 35 || y == 35 else { continue }
                XCTAssertEqual(alpha[index], 0, "\(status) 的笔画贴到了画布边缘 (\(x), \(y))")
            }
        }
    }
}
