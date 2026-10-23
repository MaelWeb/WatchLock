import CoreLocation
import Foundation

/// 为「按位置的信任场所」周期性取一次定位。
///
/// 只在有位置场所（或设置页需要展示当前位置）时才会被调用；用 `requestLocation()` 单次请求，
/// 而不是常驻 `startUpdatingLocation()`，避免持续占用定位硬件。授权由 `WiFiNameAccess` 统一管理，
/// 这里不弹授权框：没有授权就不请求，`latestFix` 也会被清空，调用方据此按「不在场所内」处理。
@MainActor
final class LocationFixProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    /// 最近一次定位结果。是否仍然有效由 `TrustedPlace.locationMaxAge` 判断。
    @Published private(set) var latestFix: TrustedPlace.LocationFix?

    /// 常规请求间隔（秒）。定位结果有效期是 120 秒，留出失败重试的余量。
    static let normalInterval: TimeInterval = 30
    /// 设置页刚打开时的最短间隔，避免用户反复进出页面时连续请求。
    static let forcedInterval: TimeInterval = 5

    private let manager = CLLocationManager()
    private var lastRequestAt: Date = .distantPast

    override init() {
        super.init()
        manager.delegate = self
        // Mac 没有 GPS，再高的档位也只是 Wi-Fi 定位；十米档足够区分百米级半径。
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    /// 已授权且距上次请求足够久时请求一次定位。
    func requestIfNeeded(authorized: Bool, force: Bool = false, now: Date = Date()) {
        guard authorized else {
            // 授权丢失后旧位置不能继续当作「在场所内」的依据。
            if latestFix != nil { latestFix = nil }
            return
        }
        let interval = force ? Self.forcedInterval : Self.normalInterval
        guard now.timeIntervalSince(lastRequestAt) >= interval else { return }
        lastRequestAt = now
        manager.requestLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // 取最新的一条；CLLocation 不是 Sendable，先在回调线程里取出需要的数值。
        guard let location = locations.last else { return }
        let fix = TrustedPlace.LocationFix(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            timestamp: location.timestamp
        )
        Task { @MainActor in self.latestFix = fix }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 单次失败不清空旧结果：它会在 `locationMaxAge` 后自然失效，期间 30 秒后会重试。
    }
}
