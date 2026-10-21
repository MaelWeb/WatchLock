import Foundation

/// 周期性探测网络环境，并驱动 `TrustedPlace.Tracker`。
///
/// 只负责「看」和「判断是否在信任场所」，**不**直接改暂停状态——暂停由 `AppSession` 叠加到
/// `SettingsStore.isPaused` 里，这样手动暂停与信任场所互不覆盖。
@MainActor
final class TrustedPlaceMonitor: ObservableObject {
    let wifiAccess: WiFiNameAccess

    /// 最近一次探测到的网络环境，设置页用它展示「当前网络」并保存为信任场所。
    @Published private(set) var snapshot = TrustedPlace.Snapshot(gatewayMAC: nil, ssid: nil)
    /// 当前所处的信任场所；不在任何场所时为 `nil`。
    private(set) var current: TrustedPlace.Place?

    private var tracker: TrustedPlace.Tracker
    private let probe: (Bool) -> TrustedPlace.Snapshot

    init(
        wifiAccess: WiFiNameAccess? = nil,
        leaveDebounce: TimeInterval = 8,
        probe: @escaping (Bool) -> TrustedPlace.Snapshot = { NetworkProbe.snapshot(includeSSID: $0) }
    ) {
        self.wifiAccess = wifiAccess ?? WiFiNameAccess()
        self.tracker = TrustedPlace.Tracker(leaveDebounce: leaveDebounce)
        self.probe = probe
    }

    /// 立即探测一次并刷新 `snapshot`（设置页打开 / 点「保存当前网络」时用）。
    @discardableResult
    func refreshSnapshot() -> TrustedPlace.Snapshot {
        let latest = probe(wifiAccess.state == .authorized)
        if latest != snapshot { snapshot = latest }
        return latest
    }

    /// 1 次探测 + 状态机推进。返回这一次的变化。
    ///
    /// 配置变化（功能被关闭、场所被清空 / 删除）按「静默重置」处理，**不**返回 `.left`：
    /// 这类变化是用户在设置里主动做的，调用方不应把它当成「离开了场所」去补锁。
    func update(places: [TrustedPlace.Place], enabled: Bool, now: Date = Date()) -> TrustedPlace.Tracker.Change {
        // 功能没用上时不探测网络（设置页打开时自己会刷新快照）。
        guard enabled, !places.isEmpty else {
            _ = tracker.reset()
            current = nil
            return .none
        }
        let latest = refreshSnapshot()
        if let id = tracker.currentPlaceID, !places.contains(where: { $0.id == id }) {
            _ = tracker.reset()
            current = nil
        }

        let change = tracker.update(snapshot: latest, places: places, now: now)
        current = tracker.currentPlaceID.flatMap { id in places.first { $0.id == id } }
        return change
    }

    /// 清空状态（应用停止监听时用）。
    func reset() {
        _ = tracker.reset()
        current = nil
    }
}
