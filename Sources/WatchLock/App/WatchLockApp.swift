import SwiftUI

@main
struct WatchLockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = AppSession.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(session)
        } label: {
            HStack(spacing: 4) {
                Image(nsImage: MenuBarIcon.image(for: session.status))
                    .accessibilityLabel(session.status.title)
                if session.settings.showRSSIInMenuBar {
                    Text(session.status.shortTitle)
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
