import AppKit
import CoreLocation
import CoreWLAN
import Foundation

/// 为了读到 Wi-Fi 名称（SSID）而申请的定位授权，以及 SSID 的读取。
///
/// **这是「信任场所」的可选增强，不是前提**：网关指纹（`NetworkProbe`）不需要任何授权就能工作。
/// SSID 的作用只是让用户在列表里看到更友好的名字，并在「网关 MAC 相同但换了 Wi-Fi 名」时多一道否决。
///
/// 依据（均已标明查证程度）：
/// - Apple 文档《Requesting authorization to use location services》：macOS 上 When in Use 与 Always
///   功能等价；macOS 专用的 Info.plist 键是 `NSLocationUsageDescription`；授权请求在缺键时会立即失败。（已核对原文）
/// - 本机实测：未授权进程里 `CWInterface.ssid()` 为 `nil`。（已实测）
/// - Apple 开发者论坛 / 社区反馈：macOS 14 起 SSID 受定位授权控制。（论坛原帖被反爬拦截，**未取得一手原文**）
/// - ad-hoc 签名下授权能否跨版本保留：**待验证**。DTS 对 TCC 的说法是需要「能逐次构建追踪的签名身份」，
///   我们没有开发者账号，所以升级后授权很可能丢失，需要用户重新授权；功能必须能在没有 SSID 时继续工作。
/// - `LSUIElement` 菜单栏 App 的授权弹窗能否正常出现：**待真机验证**（见 `requestAuthorization()` 里的激活处理）。
@MainActor
final class WiFiNameAccess: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum State: Equatable {
        /// 系统定位服务整体关闭。
        case servicesDisabled
        case notDetermined
        case denied
        case authorized

        var title: String {
            switch self {
            case .servicesDisabled: return String(localized: "系统定位服务已关闭")
            case .notDetermined: return String(localized: "尚未授权")
            case .denied: return String(localized: "已拒绝")
            case .authorized: return String(localized: "已授权")
            }
        }
    }

    @Published private(set) var state: State = .notDetermined

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        refresh()
    }

    /// 纯函数：把系统的授权状态折算成界面状态。
    nonisolated static func state(from status: CLAuthorizationStatus, servicesEnabled: Bool) -> State {
        guard servicesEnabled else { return .servicesDisabled }
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted, .denied: return .denied
        case .authorizedAlways: return .authorized
        @unknown default: return .notDetermined
        }
    }

    func refresh() {
        state = Self.state(from: manager.authorizationStatus, servicesEnabled: CLLocationManager.locationServicesEnabled())
    }

    /// 请求授权。菜单栏 App 没有前台窗口时系统可能不显示弹窗，所以先临时激活自己。
    func requestAuthorization() {
        NSApp.activate(ignoringOtherApps: true)
        manager.requestWhenInUseAuthorization()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.refresh() }
    }
}

/// 读取 SSID 的最小封装：放在单独类型里，方便 `NetworkProbe` 不直接依赖 CoreWLAN。
enum CWWiFiClientBridge {
    static func ssid() -> String? {
        CWWiFiClient.shared().interface()?.ssid()
    }
}
