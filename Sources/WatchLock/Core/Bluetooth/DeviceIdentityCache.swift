import Foundation

/// 按外设标识缓存「名称 / AirPods 型号」。
///
/// 存在的原因：Local Name 与 Proximity Pairing 都是**间歇性**出现在广播里的，同一台设备这一帧有、
/// 下一帧没有。直接用最新一帧会让列表里的名称、图标来回跳。
/// 缓存只对**同一个 identifier** 生效；蓝牙地址轮换后 identifier 会变，那种情况无法靠缓存续上。
struct DeviceIdentityCache {
    private struct Entry {
        var name: String?
        var model: AirPodsModel?
        /// 最近一次看到这台设备的时间；过期按它算，所以持续在场的设备不会丢名字。
        var lastSeen: Date
    }

    /// 超过这个时间没再看到设备，缓存作废。
    let timeToLive: TimeInterval
    /// 条目上限：周围可能有上百台 Apple 设备，不设上限会无限增长。
    let capacity: Int
    private var entries: [UUID: Entry] = [:]

    init(timeToLive: TimeInterval = 6 * 60 * 60, capacity: Int = 512) {
        self.timeToLive = timeToLive
        self.capacity = capacity
    }

    var count: Int { entries.count }

    /// 记录一次广播。`name` / `model` 为 nil 表示这一帧没带，不会覆盖已缓存的值。
    mutating func record(id: UUID, name: String?, model: AirPodsModel?, now: Date) {
        let cleanName = name.flatMap { $0.isEmpty ? nil : $0 }

        if var entry = entries[id] {
            // 已过期的旧值不能被「续命」：先清掉再写入新值。
            if now.timeIntervalSince(entry.lastSeen) > timeToLive {
                entry = Entry(name: nil, model: nil, lastSeen: now)
            }
            entry.name = cleanName ?? entry.name
            entry.model = model ?? entry.model
            entry.lastSeen = now
            entries[id] = entry
            return
        }

        // 这一帧什么身份信息都没带，也没有旧缓存：不值得占一个条目。
        guard cleanName != nil || model != nil else { return }
        entries[id] = Entry(name: cleanName, model: model, lastSeen: now)
        evictOldestIfNeeded()
    }

    func name(for id: UUID, now: Date) -> String? {
        liveEntry(for: id, now: now)?.name
    }

    func model(for id: UUID, now: Date) -> AirPodsModel? {
        liveEntry(for: id, now: now)?.model
    }

    /// 清掉已过期的条目。
    mutating func prune(now: Date) {
        entries = entries.filter { now.timeIntervalSince($0.value.lastSeen) <= timeToLive }
    }

    private func liveEntry(for id: UUID, now: Date) -> Entry? {
        guard let entry = entries[id], now.timeIntervalSince(entry.lastSeen) <= timeToLive else { return nil }
        return entry
    }

    private mutating func evictOldestIfNeeded() {
        while entries.count > capacity,
              let oldest = entries.min(by: { $0.value.lastSeen < $1.value.lastSeen })?.key {
            entries.removeValue(forKey: oldest)
        }
    }
}
