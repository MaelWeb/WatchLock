import SwiftUI

/// 品牌标识。
///
/// 应用图标 `Resources/AppIcon.icns`（Dock / Finder / 关于页）由
/// `Scripts/generate-icons.sh` 从 `docs/logo/AppIcon-master.png` 生成。
///
/// 菜单栏里用的是**状态图标**（见 `MenuBarIcon`，由 logo 的「环形锁体 + 锁梁」提炼并用代码绘制），
/// 因为那里要一眼看出状态；品牌 logo 只用于关于页等「身份展示」场景。
enum BrandLogo {
    static let name = "WatchLock"

    /// 品牌图标（关于页等展示场景）。
    ///
    /// 找不到资源时回退到 SF Symbol，避免图标缺失导致空白。
    static var image: Image {
        if let nsImage = Bundle.main.image(forResource: "AppIcon") {
            return Image(nsImage: nsImage)
        }
        return Image(systemName: "lock.shield")
    }

    /// 应用图标（`AppIcon.icns`），用于 Dock / ⌘⇥ / 系统权限列表。
    static var appIcon: NSImage? {
        Bundle.main.image(forResource: "AppIcon")
    }
}

/// 品牌图标：圆角裁切 + 阴影，尺寸自适应。
struct BrandLogoView: View {
    var size: CGFloat = 72

    var body: some View {
        BrandLogo.image
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
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
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                .accessibilityHidden(true)
            Text(BrandLogo.name)
                .font(font)
            Spacer(minLength: 0)
        }
    }
}
