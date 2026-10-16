import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // 显式指定应用图标：从命令行直接启动二进制时不会走 LaunchServices 注册，
        // 系统权限列表 / ⌘⇥ 里可能显示默认图标；这里按包内 AppIcon.icns 固定。
        if let icon = BrandLogo.appIcon {
            NSApp.applicationIconImage = icon
        }
        DiagnosticsLog.shared.append(.info, "应用启动")
        Task { @MainActor in
            AppSession.shared.start()
            if !SettingsStore.shared.hasCompletedOnboarding {
                OnboardingWindow.present(session: AppSession.shared)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            AppSession.shared.stop()
        }
        DiagnosticsLog.shared.append(.info, "应用退出")
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
