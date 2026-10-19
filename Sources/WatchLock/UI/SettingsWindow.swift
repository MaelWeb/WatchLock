import SwiftUI

/// 设置窗口的宿主（LSUIElement 应用没有主窗口，直接用 `NSWindow` 承载）。
///
/// 不用 SwiftUI 的 `Settings` scene：它的窗口由系统创建，事后再给 `styleMask` 追加
/// `.fullSizeContentView`，SwiftUI 宿主视图不会重新铺满到标题栏下方，内容始终停在
/// 标题栏下面，系统标题栏（底色 + 通栏分隔线）就会暴露出来，与侧栏 / 详情色不一致。
/// 自建窗口时在创建那一刻就带上 `.fullSizeContentView`，与引导窗口完全同构。
@MainActor
enum SettingsWindow {
    static func present(session: AppSession) {
        if let window = current {
            bringToFront(window)
            return
        }

        let root = SettingsView().environmentObject(session)
        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "WatchLock 设置")
        // 去掉原生标题栏条：隐藏标题文字、标题栏透明、不画标题栏底部分隔线；
        // 红绿灯仍保留并悬浮在内容之上。
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.contentMinSize = NSSize(width: 680, height: 620)
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.center()
        current = window
        bringToFront(window)
    }

    private static var current: NSWindow?
    private static var activationObserver: NSObjectProtocol?

    /// 把设置窗口带到所有窗口最前面。
    ///
    /// 从菜单栏 popover 点「设置…」时应用是 accessory 策略且并非前台：
    /// - popover 面板此刻还没收起，同步调用 `activate` 会被 macOS 14 的协作式激活忽略；
    /// - 所以延后一拍，等 popover 让出焦点后再激活；
    /// - 激活生效前先临时抬到 `.floating` 并 `orderFrontRegardless`，保证不会被别的 App 的窗口盖住，
    ///   应用真正成为前台后再恢复 `.normal`，避免窗口一直压在其他 App 之上。
    private static func bringToFront(_ window: NSWindow) {
        DispatchQueue.main.async {
            window.level = .floating
            NSApp.activate(ignoringOtherApps: true)
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            restoreNormalLevelWhenActive(window)
        }
    }

    private static func restoreNormalLevelWhenActive(_ window: NSWindow) {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        if NSApp.isActive {
            window.level = .normal
            return
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                window.level = .normal
                if let observer = activationObserver {
                    NotificationCenter.default.removeObserver(observer)
                    activationObserver = nil
                }
            }
        }
    }
}
