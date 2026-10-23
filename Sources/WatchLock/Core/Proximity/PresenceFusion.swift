import Foundation

/// 用户选作「辅助信号源」的设备（iPhone、AirPods 等）。
///
/// 只记录能用来续接的最少信息：蓝牙外设标识、名称、广播类型指纹。
/// Apple 设备以随机地址（RPA）广播，地址会轮换，所以 `id` 可能变——名称为空的设备轮换后无法续接，
/// 此时它只是「不再提供证据」，**不会**带来任何额外的锁定或不锁定，见 `PresenceFusion` 的说明。
struct AuxiliaryDevice: Codable, Equatable, Identifiable {
    /// 蓝牙外设标识（`UUID.uuidString`）。
    var id: String
    var name: String
    /// 绑定时记录的广播类型指纹（`AppleAdvertisement.Payload.fingerprint`）。
    var advertisement: String?
    /// 添加时记录的 AirPods 型号快照：耳机入耳后不再发 Proximity Pairing 广播，型号只能趁早存下来。
    /// 可选字段，旧版本保存的数据解码时为 nil。
    var airPodsModel: AirPodsModel?

    var displayName: String {
        name.isEmpty ? String(localized: "未命名设备") : name
    }
}

/// 多信号源融合：让 iPhone / AirPods 作为**辅助**证据，减少「手表广播断了但人还在」的误锁。
///
/// ## 语义（刻意保守）
///
/// 辅助设备只有「延缓」一种权力：
/// 1. **只延缓「信号丢失」**。手表是主信号源；`ProximityEngine` 因为「超过设定时间没收到手表广播」
///    判定离开时，如果此刻某个辅助设备明确在附近，就暂缓锁定。
///    而「手表信号明确很弱」（`beyondThreshold`）说明手表就在远处，**辅助设备不能否决**——
///    把手机落在桌上走开是最常见的场景，用手机在场去推翻手表的明确读数会让锁屏失效。
/// 2. **不能触发锁定**。没有手表信号时辅助设备再远也不会锁屏，锁屏仍然只由手表驱动。
/// 3. **有硬上限**（`Config.maxHold`，默认 2 分钟）。到点无论辅助设备是否还在都放行，
///    防止「手机忘在桌上」让锁屏长期失效。
/// 4. **任何不确定都往「锁」的方向落**：辅助设备读不到、过期、地址轮换续不上、功能被关闭，
///    一律视为没有证据，退回只看手表的行为。
///
/// ## 依据与未验证项
/// - Apple 设备广播会随设备状态启停，且地址轮换，第三方拿不到 IRK（`docs/anti-false-lock-research.md`）。
///   这正是「手表十几秒没广播但人还在」的来源，也是辅助证据能帮上忙的地方。
/// - 本机实测周边 BLE：iPhone 与手表同为 Continuity 类型 `0x10`，无法靠类型字节区分设备，
///   所以辅助设备必须由用户从列表里点选，不做自动识别。
/// - **未验证**：默认的辅助「在附近」阈值（`-80 dBm`）是按「桌前约 -70 ~ -85」的经验取的，
///   没有用真实 iPhone / AirPods 逐一标定；iPhone 息屏后其广播会停止（论坛报告，未取得一手原文），
///   所以实际效果是「手机亮屏或被使用时才能提供证据」。
/// - **未验证**：AirPods 在耳中 / 在盒中是否发出可区分的广播，没有实测，因此不区分「佩戴」与「在盒中」。
enum PresenceFusion {
    /// 最多选几个辅助设备。
    static let maxDevices = 3

    struct Config: Equatable {
        var enabled = false
        /// 辅助设备「在附近」的 RSSI 下限（含）。
        var nearRSSI = -80
        /// 只采信最近这么多秒内的读数；窗口内取最强的一次，抵抗单次抖动。
        var freshness: TimeInterval = 20
        /// 暂缓锁定的硬上限。
        var maxHold: TimeInterval = 120
    }

    // MARK: - 证据

    /// 辅助设备的近期读数。
    struct Evidence {
        private var readings: [String: [(rssi: Int, date: Date)]] = [:]

        /// 记录一次读数，并丢弃窗口外的旧读数。
        mutating func record(id: String, rssi: Int, at date: Date, window: TimeInterval) {
            var list = readings[id, default: []]
            list.append((rssi, date))
            list.removeAll { date.timeIntervalSince($0.date) > window }
            readings[id] = list
        }

        /// 只保留仍被选中的设备（用户移除设备后清理）。
        mutating func keepOnly(_ ids: Set<String>) {
            readings = readings.filter { ids.contains($0.key) }
        }

        /// 地址轮换续接：把旧标识下的读数挪到新标识。
        mutating func move(from old: String, to new: String) {
            guard old != new, let list = readings.removeValue(forKey: old) else { return }
            readings[new, default: []] += list
        }

        mutating func reset() { readings = [:] }

        /// 窗口内最强的一次读数；没有则为 `nil`。
        func bestRSSI(id: String, now: Date, window: TimeInterval) -> Int? {
            readings[id]?
                .filter { now.timeIntervalSince($0.date) <= window }
                .map(\.rssi)
                .max()
        }

        /// 此刻明确在附近的设备标识（排序后，便于稳定展示与测试）。
        func nearIDs(now: Date, config: Config) -> [String] {
            readings.keys
                .filter { id in
                    guard let best = bestRSSI(id: id, now: now, window: config.freshness) else { return false }
                    return best >= config.nearRSSI
                }
                .sorted()
        }
    }

    // MARK: - 暂缓状态机

    /// 手表一侧的现状，由调用方从 `ProximityEngine` 取。
    struct WatchView: Equatable {
        /// 状态机当前是否判定为「已离开」。
        var isFar: Bool
        var lastSampleAt: Date?
        var smoothedRSSI: Double?
        var farRSSI: Int
    }

    /// 「信号丢失」触发的离开是否被辅助设备暂缓，以及何时结束。
    struct Hold {
        enum Release: Equatable {
            /// 辅助设备不再在附近（或读数过期）。
            case auxiliaryGone
            /// 暂缓期间手表重新出现且信号明确很弱：手表自己说它在远处，不再等。
            case watchConfirmedFar
            /// 达到硬上限。
            case capped
            /// 功能被关闭。
            case disabled
        }

        enum Tick: Equatable {
            case idle
            case holding
            /// 手表回到身边 / 状态机不再是「已离开」：放弃暂缓，不需要补锁。
            case cancelled
            /// 暂缓结束，调用方应把原来的离开交给后续闸门继续处理（通常就是锁屏）。
            case release(Release, ProximityEngine.FarReason)
        }

        private(set) var since: Date?
        private(set) var reason: ProximityEngine.FarReason?
        /// 最近一次确认在附近的辅助设备标识，仅供界面提示。
        private(set) var holders: [String] = []

        var isHolding: Bool { since != nil }

        /// 状态机判定离开时调用。返回 `true` 表示暂缓（调用方不要锁屏）。
        mutating func request(
            reason: ProximityEngine.FarReason,
            nearIDs: [String],
            now: Date,
            config: Config
        ) -> Bool {
            // 只有「信号丢失」可被辅助设备暂缓；手表明确很弱时辅助设备没有否决权。
            guard config.enabled, reason == .signalLost, !nearIDs.isEmpty else { return false }
            if since == nil {
                since = now
                self.reason = reason
            }
            holders = nearIDs
            return true
        }

        /// 1 秒一次的结算。
        mutating func tick(now: Date, config: Config, nearIDs: [String], watch: WatchView) -> Tick {
            guard let since, let reason else { return .idle }
            guard watch.isFar else {
                clear()
                return .cancelled
            }
            guard config.enabled else { return release(.disabled, reason) }
            if let sampleAt = watch.lastSampleAt, sampleAt > since,
               let rssi = watch.smoothedRSSI, rssi <= Double(watch.farRSSI) {
                return release(.watchConfirmedFar, reason)
            }
            if now.timeIntervalSince(since) >= config.maxHold { return release(.capped, reason) }
            guard !nearIDs.isEmpty else { return release(.auxiliaryGone, reason) }
            holders = nearIDs
            return .holding
        }

        /// 手表回到身边、暂停 / 关闭、整机睡眠、会话已锁定等：放弃暂缓。
        mutating func cancel() { clear() }

        private mutating func release(
            _ release: Release,
            _ reason: ProximityEngine.FarReason
        ) -> Tick {
            clear()
            return .release(release, reason)
        }

        private mutating func clear() {
            since = nil
            reason = nil
            holders = []
        }
    }

    // MARK: - 地址轮换续接

    /// 辅助设备的蓝牙地址轮换后，在已发现的设备里找它的新地址。
    ///
    /// 复用手表的续接规则（`WatchMatcher.shouldRebind`：名称一致，且广播类型指纹不冲突）。
    /// 名称为空的设备续不上——这是预期的：续不上只意味着不再提供证据，会退回只看手表。
    /// - Parameter taken: 已被其它辅助设备或手表占用的标识，避免两个设备续接到同一个地址。
    static func rebindTarget(
        for device: AuxiliaryDevice,
        among discovered: [DiscoveredWatch],
        taken: Set<String>
    ) -> DiscoveredWatch? {
        discovered
            .filter { candidate in
                !taken.contains(candidate.id.uuidString)
                    && WatchMatcher.shouldRebind(
                        boundIdentifier: device.id,
                        boundName: device.name,
                        candidateIdentifier: candidate.id,
                        candidateName: candidate.name,
                        boundAdvertisement: device.advertisement,
                        candidateManufacturerData: candidate.manufacturerData
                    )
            }
            .max { $0.rssi < $1.rssi }
    }
}
