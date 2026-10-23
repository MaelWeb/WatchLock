import Foundation

/// 让「绑定候选列表」保持稳定：出现过的设备不会因为信号抖动而瞬间消失，行也不会来回跳。
///
/// 此前的列表是每次刷新都重新取「当前信号最强的 8 台」：
/// - RSSI 是单个广播包的瞬时值，排在第 8 名上下的设备会在列表里进进出出，用户还没点绑定就没了；
/// - 排序键是瞬时 RSSI，行位置每秒都在变，点击目标会从鼠标下面滑走。
///
/// 现在的规则：
/// 1. **入选**：沿用 `mergedBindingList`（强候选 + 信号最强的若干台），入选后就「钉住」；
/// 2. **保留**：钉住的设备只要还在广播就一直留着，哪怕信号掉出了前几名；
///    连续 `hold` 秒没有广播才移除（强候选由扫描器的 30 分钟清理兜底）；
/// 3. **排序**：用平滑后的信号分档，同档内保持先来后到，档位只在信号明显变化时才变；
/// 4. **上限**：钉住的设备超过 `maxVisible` 时，先淘汰平滑信号最弱的非强候选。
struct BindingListTracker {
    struct Config {
        /// 每次入选时参考的「信号最强」名额，同 `mergedBindingList` 的 `limit`。
        var limit = 8
        /// 非强候选连续多久没有广播就移除（秒）。Apple 设备广播时断时续，太短会误删。
        var hold: TimeInterval = 90
        /// 列表总上限，防止周围设备很多时越钉越长。
        var maxVisible = 16
        /// 指数平滑系数：越大越跟手，越小越稳。
        var smoothing = 0.3
        /// 排序分档宽度（dBm）：同一档内不按信号重排，避免行位置抖动。
        var bucketWidth = 5.0
        /// 入选时的优先顺序（决定「信号最强的若干台」怎么挑）。默认按信号；
        /// 辅助设备列表会让有名称的设备优先，因为无名广播地址一轮换就无法续接。
        var admissionOrder: (DiscoveredWatch, DiscoveredWatch) -> Bool = DiscoveredWatch.isRankedBefore
    }

    private struct Entry {
        var device: DiscoveredWatch
        var smoothedRSSI: Double
        /// 入选顺序，同档内按它排，保证行位置稳定。
        var order: Int
        var isStrong: Bool
    }

    let config: Config
    private var entries: [UUID: Entry] = [:]
    private var nextOrder = 0

    init(config: Config = Config()) {
        self.config = config
    }

    /// 当前应展示的设备，已排好序。
    var visible: [DiscoveredWatch] {
        entries.values
            .sorted { lhs, rhs in
                let lhsBucket = bucket(of: lhs.smoothedRSSI)
                let rhsBucket = bucket(of: rhs.smoothedRSSI)
                if lhsBucket != rhsBucket { return lhsBucket > rhsBucket }
                return lhs.order < rhs.order
            }
            .map(\.device)
    }

    /// 用最新的扫描结果刷新列表。
    /// - Parameters:
    ///   - strong: 强候选（名称 / 服务 UUID / 已绑定）。
    ///   - all: 扫描到的全部设备。
    mutating func update(strong: [DiscoveredWatch], all: [DiscoveredWatch], now: Date) {
        let strongByID = Dictionary(strong.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let allByID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        refreshExisting(strongByID: strongByID, allByID: allByID, now: now)
        admitNewDevices(strong: strong, all: all, strongByID: strongByID, now: now)
        evictOverflow()
    }

    // MARK: - 步骤

    private mutating func refreshExisting(
        strongByID: [UUID: DiscoveredWatch],
        allByID: [UUID: DiscoveredWatch],
        now: Date
    ) {
        for (id, var entry) in entries {
            guard let latest = strongByID[id] ?? allByID[id] else {
                entries[id] = nil
                continue
            }
            let isStrong = strongByID[id] != nil
            if !isStrong, now.timeIntervalSince(latest.lastSeen) > config.hold {
                entries[id] = nil
                continue
            }
            entry.device = Self.withDefaultReason(latest)
            entry.isStrong = isStrong
            entry.smoothedRSSI = smoothed(previous: entry.smoothedRSSI, sample: latest.rssi)
            entries[id] = entry
        }
    }

    private mutating func admitNewDevices(
        strong: [DiscoveredWatch],
        all: [DiscoveredWatch],
        strongByID: [UUID: DiscoveredWatch],
        now: Date
    ) {
        // 太久没广播的设备（扫描器里还留着 30 分钟）不该因为「最后一次信号很强」而入选。
        let recent = all.filter { now.timeIntervalSince($0.lastSeen) <= config.hold }
        let admitted = DiscoveredWatch.mergedBindingList(
            strong: strong,
            all: recent,
            limit: config.limit,
            admissionOrder: config.admissionOrder
        )
        for device in admitted where entries[device.id] == nil {
            entries[device.id] = Entry(
                device: Self.withDefaultReason(device),
                smoothedRSSI: Double(device.rankingRSSI),
                order: nextOrder,
                isStrong: strongByID[device.id] != nil
            )
            nextOrder += 1
        }
    }

    private mutating func evictOverflow() {
        while entries.count > config.maxVisible,
              let weakest = entries
                  .filter({ !$0.value.isStrong })
                  .min(by: { lhs, rhs in
                      if lhs.value.smoothedRSSI != rhs.value.smoothedRSSI {
                          return lhs.value.smoothedRSSI < rhs.value.smoothedRSSI
                      }
                      // 信号一样弱时淘汰更晚入选的，让先来的保持稳定。
                      return lhs.value.order > rhs.value.order
                  })?.key {
            entries.removeValue(forKey: weakest)
        }
    }

    // MARK: - 工具

    /// RSSI ≥ 0 是「未知」，不参与平滑；之前也没有有效值时保持「最弱」。
    private func smoothed(previous: Double, sample: Int) -> Double {
        guard sample < 0 else { return previous }
        let unknown = Double(DiscoveredWatch.unknownRankingRSSI)
        guard previous > unknown else { return Double(sample) }
        return previous + config.smoothing * (Double(sample) - previous)
    }

    private func bucket(of rssi: Double) -> Int {
        Int((rssi / config.bucketWidth).rounded(.down))
    }

    private static func withDefaultReason(_ device: DiscoveredWatch) -> DiscoveredWatch {
        guard device.matchReasons.isEmpty else { return device }
        var copy = device
        copy.matchReasons = [DiscoveredWatch.nearMacReason]
        return copy
    }
}
