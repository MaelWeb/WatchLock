import XCTest
import AppKit
@testable import WatchLock

/// 应用图标源文件（`Resources/AppIcon.icon`）的规范守护。
///
/// 依据 Apple HIG · App icons：macOS 26 起图标由系统统一遮罩并生成高光，
/// 提供的图层必须是「方形、未遮罩」的；背景图层要铺满画布且不透明；不要自带圆角 / 阴影 / 留白。
/// 之前母版曾是「带圆角 + 四周留白 + 假透明棋盘格」的位图，进了 `.icns` 后关于页图标外圈露灰点，
/// 这里把规则固化下来，换图时一旦违反就会失败。
final class AppIconSourceTests: XCTestCase {

    private static let canvas = 1024

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WatchLockTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // 仓库根
    }
    private var iconDir: URL { repoRoot.appendingPathComponent("Resources/AppIcon.icon") }

    // MARK: - 像素读取

    private struct Pixels {
        let width: Int
        let height: Int
        let data: [UInt8]   // RGBA，非预乘以外的值只用 alpha

        func alpha(_ x: Int, _ y: Int) -> UInt8 { data[(y * width + x) * 4 + 3] }
    }

    private func loadPixels(_ url: URL) throws -> Pixels {
        let image = try XCTUnwrap(NSImage(contentsOf: url), "读不到图片：\(url.lastPathComponent)")
        let cg = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let width = cg.width, height = cg.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = try XCTUnwrap(CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Pixels(width: width, height: height, data: data)
    }

    // MARK: - 结构

    func testIconDocumentReferencesExistingLayers() throws {
        let json = try Data(contentsOf: iconDir.appendingPathComponent("icon.json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let groups = try XCTUnwrap(root["groups"] as? [[String: Any]])
        let names = groups
            .flatMap { ($0["layers"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["image-name"] as? String }
        XCTAssertEqual(Set(names), ["background.png", "glyph.png"], "图层应只有背景 + 锁形")
        for name in names {
            let path = iconDir.appendingPathComponent("Assets/\(name)").path
            XCTAssertTrue(FileManager.default.fileExists(atPath: path), "icon.json 引用了不存在的图层：\(name)")
        }
    }

    func testBundleDeclaresIconNameForAssetCatalogIcon() throws {
        let plist = repoRoot.appendingPathComponent("Resources/Info.plist")
        let dict = try XCTUnwrap(NSDictionary(contentsOf: plist) as? [String: Any])
        XCTAssertEqual(dict["CFBundleIconName"] as? String, "AppIcon", "缺少 CFBundleIconName，macOS 26 找不到 Assets.car 里的图标")
        XCTAssertEqual(dict["CFBundleIconFile"] as? String, "AppIcon", "旧系统回退要靠 CFBundleIconFile")
    }

    func testNoPremaskedIcnsIsCheckedIn() {
        // 预遮罩的 .icns 会让 macOS 26 把图标缩进灰色圆角底板；图标统一由 build-app.sh 用 actool 现编。
        let stray = repoRoot.appendingPathComponent("Resources/AppIcon.icns").path
        XCTAssertFalse(FileManager.default.fileExists(atPath: stray), "不要再提交 Resources/AppIcon.icns")
    }

    // MARK: - 背景图层：铺满 + 不透明

    func testBackgroundLayerIsFullBleedOpaqueSquare() throws {
        let px = try loadPixels(iconDir.appendingPathComponent("Assets/background.png"))
        XCTAssertEqual(px.width, Self.canvas)
        XCTAssertEqual(px.height, Self.canvas)

        // 完全不透明 = 没有圆角、没有四周留白、没有（假）透明背景。
        var firstTransparent: (Int, Int)?
        outer: for y in 0 ..< px.height {
            for x in 0 ..< px.width where px.alpha(x, y) != 255 {
                firstTransparent = (x, y)
                break outer
            }
        }
        XCTAssertNil(firstTransparent, "背景图层出现非不透明像素：\(String(describing: firstTransparent))")

        // 四个角必须有颜色（不是被圆角裁掉后留下的白 / 灰）：与相邻内部像素同色系，即不应是近白色。
        for (x, y) in [(0, 0), (px.width - 1, 0), (0, px.height - 1), (px.width - 1, px.height - 1)] {
            let i = (y * px.width + x) * 4
            let minChannel = min(px.data[i], px.data[i + 1], px.data[i + 2])
            XCTAssertLessThan(minChannel, 200, "角点 (\(x), \(y)) 近乎白色，像是预先做过圆角 / 留白")
        }
    }

    // MARK: - 前景图层：透明底 + 不贴边

    func testGlyphLayerHasTransparentBackgroundAndSafeMargin() throws {
        let px = try loadPixels(iconDir.appendingPathComponent("Assets/glyph.png"))
        XCTAssertEqual(px.width, Self.canvas)
        XCTAssertEqual(px.height, Self.canvas)

        XCTAssertEqual(px.alpha(0, 0), 0, "前景图层四角应透明")
        XCTAssertEqual(px.alpha(px.width - 1, px.height - 1), 0)

        var minX = px.width, minY = px.height, maxX = -1, maxY = -1
        for y in 0 ..< px.height {
            for x in 0 ..< px.width where px.alpha(x, y) > 127 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        XCTAssertGreaterThanOrEqual(maxX, 0, "前景图层是空的")

        // 系统会把画布裁成圆角方形：锁形离边至少留 6%，否则四角处会被遮罩切掉。
        let safe = Int(Double(Self.canvas) * 0.06)
        XCTAssertGreaterThanOrEqual(minX, safe, "锁形太靠左")
        XCTAssertGreaterThanOrEqual(minY, safe, "锁形太靠上")
        XCTAssertLessThanOrEqual(maxX, Self.canvas - 1 - safe, "锁形太靠右")
        XCTAssertLessThanOrEqual(maxY, Self.canvas - 1 - safe, "锁形太靠下")
        // 也别太小：占画布宽度至少一半，否则 Dock 里一缩就看不清。
        XCTAssertGreaterThan(maxX - minX + 1, Self.canvas / 2)
    }
}
