import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // 不要在这里设置 `NSApp.applicationIconImage`：那会用一张平面位图盖掉系统按
        // `CFBundleIconName` 从 Assets.car 合成的图标（macOS 26 的 Liquid Glass / 深色 / 着色外观）。
        DiagnosticsLog.shared.append(.info, String(localized: "应用启动"))
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
        DiagnosticsLog.shared.append(.info, String(localized: "应用退出"))
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
