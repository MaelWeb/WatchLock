import SwiftUI

/// 品牌标识。
///
/// 应用图标的唯一源是 `Resources/AppIcon.icon`（Icon Composer 文档），由 `Scripts/build-app.sh`
/// 用 `actool` 编译进 App：`Assets.car`（macOS 26，系统负责圆角遮罩 / 高光 / 深色与着色外观）
/// 加一份回退 `AppIcon.icns`（macOS 14 / 15）。形状、阴影、留白一律交给系统，代码里不要再处理。
///
/// 菜单栏里用的是**状态图标**（见 `MenuBarIcon`，由 logo 的「环形锁体 + 锁梁」提炼并用代码绘制），
/// 因为那里要一眼看出状态；品牌 logo 只用于关于页等「身份展示」场景。
enum BrandLogo {
    static let name = "WatchLock"

    /// 品牌图标（关于页等展示场景）。
    ///
    /// 取系统合成好的应用图标（与 Dock / Finder 里看到的是同一张，已含系统边距）。
    /// 没有打进 App 包的环境（`swift test`、直接跑二进制）回退到 SF Symbol，避免空白。
    static var image: Image {
        guard hasBundleIcon else { return Image(systemName: "lock.shield") }
        return Image(nsImage: NSApplication.shared.applicationIconImage)
    }

    /// 当前进程所在的 App 包是否声明了应用图标（`CFBundleIconName`）。
    static var hasBundleIcon: Bool {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") != nil
    }
}

/// 品牌图标，尺寸自适应。
///
/// 系统合成的应用图标自带圆角、阴影和四周留白，**不要再叠 `clipShape` / `shadow`**
/// （叠加会出现双重阴影，或把留白当成图标本体而裁错）。
struct BrandLogoView: View {
    var size: CGFloat = 72

    var body: some View {
        BrandLogo.image
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// 品牌标识行：图标 + 名称（侧栏顶部、引导 hero 等）。
struct BrandLockup: View {
    var size: CGFloat = 24
    var font: Font = .subheadline.weight(.semibold)

    var body: some View {
        HStack(spacing: WLSpacing.sm) {
            BrandLogo.image
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
            Text(BrandLogo.name)
                .font(font)
            Spacer(minLength: 0)
        }
    }
}
