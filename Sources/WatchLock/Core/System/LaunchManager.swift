import Foundation
import ServiceManagement

/// 登录项管理（macOS 13+ 使用 SMAppService）。
enum LaunchManager {
    static var isRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                DiagnosticsLog.shared.append(.info, String(localized: "已开启开机启动"))
            } else {
                try SMAppService.mainApp.unregister()
                DiagnosticsLog.shared.append(.info, String(localized: "已关闭开机启动"))
            }
        } catch {
            DiagnosticsLog.shared.append(.error, String(localized: "开机启动设置失败：\(error.localizedDescription)"))
        }
    }
}
