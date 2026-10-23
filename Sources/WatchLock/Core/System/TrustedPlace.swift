import Foundation

/// 「信任场所」：在家 / 办公室等已知安全的网络环境里自动暂停自动锁定。
///
/// ## 为什么用「网关 MAC」做主依据，而不是 SSID
///
/// 本机实测（macOS 26.6.1，2026-10-20）：
/// - 没有定位授权的进程里 `CWInterface.ssid()` / `bssid()` 都是 `nil`；
///   `SCDynamicStore` 里 `State:/Network/Interface/en0/AirPort` 的 SSID 是占位值，
///   `ipconfig getsummary en0` 的 SSID / BSSID 是 `<redacted>`。
/// - 默认网关的 MAC 可以不经任何授权读到（`sysctl(NET_RT_FLAGS)` 读 ARP 表，与 `arp -an` 一致）。
///
/// SSID 需要定位授权，而授权依赖 TCC 能跨版本追踪应用的签名身份。Apple DTS 的说法是
/// 「TCC 要可靠工作，调用方须用 TCC 能逐次构建追踪的代码签名身份，ad-hoc 不行」
/// （转引自社区文章，原帖 forums/thread/718331 本次未能直接抓取，**未经一手核对**）。
/// 本项目目前只有 ad-hoc 签名（无开发者账号，见 REQUIREMENTS R-07），每次升级 cdhash 都变，
/// 所以 SSID 只能当可选增强：拿得到就多一条证据，拿不到绝不影响网关指纹的判断。
///
/// ## 按位置信任（FR-19 第 10 条）
/// 网关 MAC 在「同一个地点换了网络」时失效（手机热点、有线 / Wi-Fi 切换、访客网络）。所以场所还可以是
/// 一个**位置**（经纬度 + 半径），两类场所任一命中就算在场所内。Mac 没有 GPS，定位靠 Wi-Fi / 网络，
/// 精度通常几十米到几百米（未实测，见 REQUIREMENTS R-16），所以规则偏保守：
/// - 定位精度必须不大于场所半径，否则这一次定位不能证明「在场所内」；
/// - 定位结果超过 `locationMaxAge` 没更新就当作没有（安全方向：恢复锁定）；
/// - 没有定位授权、定位失败，一律等同「不在位置场所内」。
///
/// ## 安全边界
/// 这是「暂停自动锁定」，会让该环境下的锁屏失效，所以：
/// - 只在用户**主动**把当前网络「设为信任场所」后才生效，默认没有任何场所；
/// - 网关 MAC 可以被同网段的设备伪造（ARP 欺骗），所以它是**便利性**特性而不是安全边界，文案里要写明；
/// - 离开场所（网络变了 / 断网）立即恢复，不会残留暂停。
enum TrustedPlace {
    /// 一次定位结果。
    struct LocationFix: Equatable {
        var latitude: Double
        var longitude: Double
        /// 水平精度（米），负数表示无效。
        var horizontalAccuracy: Double
        var timestamp: Date
    }

    /// 定位结果的最长有效期（秒）：监控每 30 秒左右请求一次，超过它没更新说明定位已经失败 / 被关闭。
    static let locationMaxAge: TimeInterval = 120
    /// 位置场所可选的半径（米）。下限 100：Mac 的网络定位达不到更高精度，再小只会频繁误判「不在场所内」。
    static let radiusChoices: [Double] = [100, 200, 500]
    static let defaultRadius: Double = 200

    /// 一次环境快照：网络指纹 + 可选的定位结果。
    struct Snapshot: Equatable {
        /// 默认网关的 MAC（小写、冒号分隔、每段补零，如 `00:00:5e:00:01:25`）。没有联网或读不到时为 `nil`。
        var gatewayMAC: String?
        /// Wi-Fi 名称。仅在用户授予定位权限且系统愿意返回时才有值。
        var ssid: String?
        /// 最近一次定位结果；没有授权或还没定位到时为 `nil`。
        var location: LocationFix?

        var isOnline: Bool { gatewayMAC != nil }
    }

    /// 用户保存的一个信任场所。
    struct Place: Codable, Equatable, Identifiable {
        var id: UUID = UUID()
        /// 用户可编辑的名字（默认取 SSID 或「当前网络」）。
        var name: String
        /// 网络场所的网关 MAC；位置场所为 `nil`。
        var gatewayMAC: String?
        /// 保存时拿到的 SSID，仅用于展示和辅助比对。
        var ssid: String?
        /// 位置场所的中心与半径（米）；网络场所为 `nil`。三者要么都有要么都没有。
        var latitude: Double?
        var longitude: Double?
        var radius: Double?

        /// 是否按位置判断。
        var isLocationPlace: Bool { latitude != nil && longitude != nil && radius != nil }
    }

    // MARK: - MAC 归一化

    /// 把 `arp` 风格（`0:0:5e:0:1:25`）或任意大小写 / 分隔符的 MAC 归一为 `00:00:5e:00:01:25`。
    /// 不是 6 段十六进制时返回 `nil`。全 0 与广播地址视为无效。
    static func normalizeMAC(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let parts = raw.lowercased().split(whereSeparator: { $0 == ":" || $0 == "-" })
        guard parts.count == 6 else { return nil }
        var bytes: [String] = []
        for part in parts {
            guard part.count <= 2, let value = UInt8(part, radix: 16) else { return nil }
            bytes.append(String(format: "%02x", value))
        }
        let joined = bytes.joined(separator: ":")
        if joined == "00:00:00:00:00:00" || joined == "ff:ff:ff:ff:ff:ff" { return nil }
        return joined
    }

    // MARK: - 匹配

    /// 当前环境是否落在某个信任场所内（网络场所与位置场所任一命中即可）。
    ///
    /// 网络规则：网关 MAC 必须一致。SSID 只在**双方都有值**时参与否决——
    /// 同一个网关换了 Wi-Fi 名称（用户改了名）通常不应该继续信任，但读不到 SSID 不能当成不匹配。
    static func match(_ snapshot: Snapshot, in places: [Place], now: Date = Date()) -> Place? {
        places.first { place in
            if place.isLocationPlace {
                return matchesLocation(place, fix: snapshot.location, now: now)
            }
            return matchesNetwork(place, snapshot: snapshot)
        }
    }

    private static func matchesNetwork(_ place: Place, snapshot: Snapshot) -> Bool {
        guard let mac = normalizeMAC(snapshot.gatewayMAC),
              normalizeMAC(place.gatewayMAC) == mac else { return false }
        if let current = snapshot.ssid, !current.isEmpty, let saved = place.ssid, !saved.isEmpty {
            return current == saved
        }
        return true
    }

    /// 位置规则：定位新鲜、精度不大于半径、且落在半径内。
    static func matchesLocation(_ place: Place, fix: LocationFix?, now: Date) -> Bool {
        guard let fix,
              let latitude = place.latitude, let longitude = place.longitude, let radius = place.radius,
              fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= radius,
              now.timeIntervalSince(fix.timestamp) <= locationMaxAge else { return false }
        return distance(fromLatitude: fix.latitude, longitude: fix.longitude,
                        toLatitude: latitude, longitude: longitude) <= radius
    }

    /// 两点间的大圆距离（米，haversine）。场所半径是百米量级，球面近似的误差可以忽略。
    static func distance(fromLatitude lat1: Double, longitude lon1: Double,
                         toLatitude lat2: Double, longitude lon2: Double) -> Double {
        let earthRadius = 6_371_000.0
        let phi1 = lat1 * .pi / 180
        let phi2 = lat2 * .pi / 180
        let deltaPhi = (lat2 - lat1) * .pi / 180
        let deltaLambda = (lon2 - lon1) * .pi / 180
        let a = sin(deltaPhi / 2) * sin(deltaPhi / 2)
            + cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2)
        return earthRadius * 2 * atan2(a.squareRoot(), (1 - a).squareRoot())
    }

    /// 能否把当前网络保存为信任场所，以及不能的原因（用于按钮禁用提示）。
    enum SaveCheck: Equatable {
        case ok
        case offline
        case alreadySaved(name: String)
    }

    static func canSave(_ snapshot: Snapshot, existing: [Place]) -> SaveCheck {
        guard normalizeMAC(snapshot.gatewayMAC) != nil else { return .offline }
        // 只和网络场所比：已经有一个覆盖这里的位置场所，不妨碍再保存这个网络（换了网络时它才有用）。
        if let place = match(snapshot, in: existing.filter { !$0.isLocationPlace }) {
            return .alreadySaved(name: place.name)
        }
        return .ok
    }

    /// 能否把当前位置保存为信任场所，以及不能的原因。
    enum LocationSaveCheck: Equatable {
        case ok
        /// 没有授权、还没定位到，或定位结果已过期。
        case noFix
        /// 定位精度比所选半径还差，保存了也无法可靠判断。
        case inaccurate(accuracy: Double)
        case alreadySaved(name: String)
    }

    static func canSaveLocation(
        _ fix: LocationFix?,
        radius: Double,
        existing: [Place],
        now: Date = Date()
    ) -> LocationSaveCheck {
        guard let fix, now.timeIntervalSince(fix.timestamp) <= locationMaxAge,
              fix.horizontalAccuracy >= 0,
              (-90 ... 90).contains(fix.latitude), (-180 ... 180).contains(fix.longitude) else { return .noFix }
        guard fix.horizontalAccuracy <= radius else { return .inaccurate(accuracy: fix.horizontalAccuracy) }
        let snapshot = Snapshot(gatewayMAC: nil, ssid: nil, location: fix)
        if let place = match(snapshot, in: existing.filter(\.isLocationPlace), now: now) {
            return .alreadySaved(name: place.name)
        }
        return .ok
    }

    /// 由定位结果生成位置场所。
    static func makeLocationPlace(from fix: LocationFix, name: String?, radius: Double, fallbackName: String) -> Place {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Place(
            name: trimmed.isEmpty ? fallbackName : trimmed,
            gatewayMAC: nil,
            ssid: nil,
            latitude: fix.latitude,
            longitude: fix.longitude,
            radius: radius
        )
    }

    /// 由快照生成默认场所（名字优先用 SSID）。
    static func makePlace(from snapshot: Snapshot, name: String? = nil, fallbackName: String) -> Place? {
        guard let mac = normalizeMAC(snapshot.gatewayMAC) else { return nil }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = !trimmed.isEmpty ? trimmed : (snapshot.ssid.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName)
        return Place(name: title, gatewayMAC: mac, ssid: snapshot.ssid)
    }

    // MARK: - 暂停状态机

    /// 信任场所驱动的自动暂停决策。
    ///
    /// 与用户手动暂停（`SettingsStore.pauseUntil`）完全独立：这里只产出「当前是否处于信任场所」，
    /// 由调用方叠加到「是否暂停」判断里。这样用户手动暂停到期、或手动恢复，都不会被信任场所状态覆盖。
    ///
    /// - 防抖：网络刚切换时网关 MAC 会短暂读不到（ARP 重新解析需要几秒），所以**进入**立即生效，
    ///   **离开**要连续 `leaveDebounce` 秒读不到才算，避免短暂断网触发误恢复 / 误暂停来回抖动。
    ///   注意方向：离开时「恢复锁定」才是安全方向，所以防抖的目的只是减少抖动，不能拖得太久。
    struct Tracker {
        var leaveDebounce: TimeInterval
        private(set) var currentPlaceID: UUID?
        private var missingSince: Date?

        init(leaveDebounce: TimeInterval = 8) {
            self.leaveDebounce = leaveDebounce
        }

        var isInTrustedPlace: Bool { currentPlaceID != nil }

        enum Change: Equatable {
            case none
            case entered(Place)
            case left
        }

        /// 喂入最新快照。返回这一次的状态变化。
        mutating func update(snapshot: Snapshot, places: [Place], now: Date) -> Change {
            if let place = TrustedPlace.match(snapshot, in: places, now: now) {
                missingSince = nil
                if currentPlaceID != place.id {
                    let wasInside = currentPlaceID != nil
                    currentPlaceID = place.id
                    return wasInside ? .none : .entered(place)
                }
                return .none
            }

            guard currentPlaceID != nil else { return .none }
            if let missingSince {
                if now.timeIntervalSince(missingSince) >= leaveDebounce {
                    currentPlaceID = nil
                    self.missingSince = nil
                    return .left
                }
            } else {
                missingSince = now
            }
            return .none
        }

        /// 用户删除了场所 / 关闭了功能：立即清空，不走防抖。
        mutating func reset() -> Change {
            defer { currentPlaceID = nil; missingSince = nil }
            return currentPlaceID != nil ? .left : .none
        }
    }
}
