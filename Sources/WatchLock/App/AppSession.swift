import Combine
import CoreBluetooth
import Foundation
import SwiftUI

/// 应用主控制器：串联扫描 → 距离判断 → 锁定/解锁。
@MainActor
final class AppSession: ObservableObject {
    static let shared = AppSession()

    let settings = SettingsStore.shared
    let scanner = WatchScanner()
    let engine = ProximityEngine(config: SettingsStore.shared.proximityConfig)
    let monitor = SleepWakeMonitor()
    /// 监听期间阻止 App Nap（仅在启用且未暂停时持有）。
    private let activity = MonitoringActivity()
    lazy var unlocker = UnlockService(settings: settings, isScreenLocked: { [weak self] in
        self?.monitor.refreshSessionLockState() ?? false
    })
    /// 自动锁定闸门：会议 / 演示豁免与手动解锁后重新布防（均默认关闭）。
    lazy var lockGate = LockGate(config: { [weak self] in self?.settings.lockGateConfig ?? .init() })
    /// 信任场所：探测网络环境，进入已保存的场所时暂停自动锁定（规则见 `TrustedPlace`）。
    let trustedPlaces = TrustedPlaceMonitor()
    /// 锁定记录（FR-21）：每次真正执行的锁定留一条，重启后仍在。
    let lockHistory = LockHistoryStore.shared

    /// 菜单栏提示：自动锁定因会议 / 演示被暂缓。
    @Published private(set) var lockDeferralNote: String?
    /// 菜单栏提示：手表信号丢失，但辅助设备在附近，锁定被暂缓（规则见 `PresenceFusion`）。
    @Published private(set) var fusionNote: String?

    @Published private(set) var status: ProximityStatus = .unknown
    @Published private(set) var smoothedRSSI: Double = 0
    @Published private(set) var estimatedDistance: Double = 0
    @Published private(set) var lastSeen: Date?
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var scannerMessage: String?
    /// 最近一次自动锁定的时间，用于「刚才误锁了」反馈入口。
    @Published private(set) var lastAutoLockAt: Date?
    @Published private(set) var falseLockFeedbackAvailable = false
    /// 最近一次自动调参的说明文案。
    @Published private(set) var tuningMessage: String?
    /// 最近一次锁定的原因（超出距离 / 信号丢失 / 手动）及时间，用于排查误锁；仅本次运行内有效。
    @Published private(set) var lastLockReason: String?
    @Published private(set) var lastLockAt: Date?

    /// 当前正在模拟的 RSSI（nil 表示未模拟）。模拟期间真实广播被忽略。
    @Published private(set) var simulatedRSSI: Int?

    private var wakeGraceUntil: Date = .distantPast
    private var isRunning = false
    /// 模拟信号注入定时器：状态机需要连续样本才会跨过 dwell 判定。
    private var simulationTimer: Timer?
    /// 未绑定手表时模拟信号使用的固定标识，避免与其它设备的真实上报混淆。
    private let simulationIdentifier = UUID(uuidString: "00000000-0000-0000-0000-00000000DEB1")!
    private var cancellables: Set<AnyCancellable> = []
    /// 1 秒一次的 housekeeping：暂停到期恢复、候选清理、状态刷新（FR-06 / FR-02 / FR-12）。
    private var housekeepingTimer: Timer?
    /// 绑定候选列表的稳定器与它的输出（发布出来让设备页随之刷新）。
    private var bindingTracker = BindingListTracker()
    @Published private(set) var bindingList: [DiscoveredWatch] = []
    /// 辅助设备候选：有名称的设备优先入选；最多 8 台，同样钉住。
    private var auxiliaryTracker = BindingListTracker(config: .init(
        limit: 8,
        maxVisible: 16,
        admissionOrder: { lhs, rhs in
            if lhs.name.isEmpty != rhs.name.isEmpty { return !lhs.name.isEmpty }
            return DiscoveredWatch.isRankedBefore(lhs, rhs)
        }
    ))
    @Published private(set) var auxiliaryCandidateList: [DiscoveredWatch] = []
    /// 「显示全部」列表：不限名额，保留时长与扫描器的 30 分钟清理一致，只负责让顺序稳定。
    private var allDevicesTracker = BindingListTracker(config: .init(
        limit: .max,
        hold: 30 * 60,
        maxVisible: 60
    ))
    @Published private(set) var allDevicesList: [DiscoveredWatch] = []
    private var lastPruneAt: Date = .distantPast
    private let candidateTTL: TimeInterval = 30 * 60

    // 辅助信号源（iPhone / AirPods）：只能暂缓「信号丢失」造成的锁定，规则见 `PresenceFusion`。
    private var fusionEvidence = PresenceFusion.Evidence()
    private var fusionHold = PresenceFusion.Hold()
    private var lastAuxiliaryRebindAt: Date = .distantPast
    /// 信任场所的探测间隔。网络环境变化不频繁，3 秒足够，也避免每秒读一次 ARP 表。
    private let placeProbeInterval: TimeInterval = 3
    private var lastPlaceProbeAt: Date = .distantPast

    private init() {
        bind()
    }

    private func bind() {
        scanner.onRSSI = { [weak self] identifier, rssi, date in
            guard let self else { return }
            Task { @MainActor in
                // 模拟信号期间忽略真实广播，避免两者打架。
                guard self.simulatedRSSI == nil else { return }
                self.handleRSSI(identifier: identifier, rssi: rssi, date: date)
            }
        }
        scanner.onPresence = { [weak self] identifier, date in
            guard let self else { return }
            Task { @MainActor in
                guard self.simulatedRSSI == nil else { return }
                guard self.matchesBoundWatch(identifier) else { return }
                self.engine.notePresence(at: date)
                self.logPresenceWithoutRSSI()
            }
        }
        scanner.boundIdentifier = settings.boundWatchID.flatMap(UUID.init(uuidString:))
        scanner.auxiliaryIdentifiers = auxiliaryIdentifierSet()
        scanner.onAuxiliaryRSSI = { [weak self] identifier, rssi, date in
            guard let self else { return }
            Task { @MainActor in
                self.fusionEvidence.record(
                    id: identifier.uuidString,
                    rssi: rssi,
                    at: date,
                    window: self.settings.fusionConfig.freshness
                )
            }
        }

        engine.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event: event) }
        }
        engine.onSample = { [weak self] sample in
            Task { @MainActor in
                self?.smoothedRSSI = sample.smoothedRSSI
                self?.estimatedDistance = sample.estimatedDistance
            }
        }

        monitor.onWake = { [weak self] in
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                self.wakeGraceUntil = Date().addingTimeInterval(self.settings.unlockGraceAfterWake)
                self.engine.reset()
                self.cancelFusionHold()
                self.fusionEvidence.reset()
                self.updateStatus(.unknown)
                self.engine.start()
                self.scanner.start()
                DiagnosticsLog.shared.append(.info, String(localized: "系统唤醒，进入宽限期并恢复扫描"))
            }
        }
        monitor.onSleep = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                DiagnosticsLog.shared.append(.info, String(localized: "系统进入睡眠，暂停蓝牙扫描"))
                self.unlocker.cancelPendingApproach()
                self.cancelFusionHold()
                self.scanner.stop()
                self.engine.stop()
            }
        }
        monitor.onScreenLocked = { [weak self] in
            Task { @MainActor in
                self?.lockGate.cancel()
                self?.cancelFusionHold()
                self?.syncLockDeferralNote()
                self?.updateStatus(self?.engine.status ?? .unknown)
            }
        }
        monitor.onScreenUnlocked = { [weak self] in
            Task { @MainActor in
                guard let self, self.isRunning, self.settings.isEnabled, !self.settings.isPaused else { return }
                self.lockGate.screenUnlocked(watchIsFar: self.engine.status == .far)
            }
        }

        settings.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in self?.refreshConfig() }
            }
            .store(in: &cancellables)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        refreshConfig()
        monitor.start()
        engine.start()
        scanner.start()
        startHousekeeping()
        NotificationPresenter.shared.requestAuthorizationIfNeeded()
        DiagnosticsLog.shared.append(.info, String(localized: "开始监听手表距离"))
        // 调试入口：WATCHLOCK_FAKE_RSSI=-80 ./WatchLock 可持续注入固定信号。
        if let raw = ProcessInfo.processInfo.environment["WATCHLOCK_FAKE_RSSI"],
           let rssi = Int(raw) {
            startSimulating(rssi: rssi)
        }
    }

    func stop() {
        isRunning = false
        activity.stop()
        housekeepingTimer?.invalidate()
        housekeepingTimer = nil
        stopSimulating()
        unlocker.cancelPendingApproach()
        cancelFusionHold()
        trustedPlaces.reset()
        settings.activeTrustedPlaceName = nil
        scanner.stop()
        engine.stop()
        monitor.stop()
    }

    /// 手动重启蓝牙扫描（设备列表长时间为空时用于刷新）。
    func rescan() {
        scanner.stop()
        scanner.start()
        refreshConfig()
    }

    // MARK: - 调试：模拟信号（无需真的走来走去）

    /// 以 1 秒为周期持续注入固定 RSSI，用于端到端验证状态机与锁屏链路。
    func startSimulating(rssi: Int) {
        simulatedRSSI = rssi
        simulationTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.feedSimulated() }
        }
        RunLoop.main.add(timer, forMode: .common)
        simulationTimer = timer
        engine.reset()
        engine.start()
        feedSimulated()
        DiagnosticsLog.shared.append(.info, String(localized: "开始模拟信号：\(rssi) dBm"))
    }

    /// 停止注入，并把状态机恢复到「搜索中」。
    func stopSimulating() {
        guard simulatedRSSI != nil else { return }
        simulatedRSSI = nil
        simulationTimer?.invalidate()
        simulationTimer = nil
        engine.reset()
        engine.start()
        updateStatus(engine.status)
        DiagnosticsLog.shared.append(.info, String(localized: "停止模拟信号"))
    }

    /// 模拟「手表离开后彻底失联」：停止注入且不再接收真实广播，用于验证 signalLostTimeout。
    func simulateSignalLoss() {
        simulatedRSSI = -127
        simulationTimer?.invalidate()
        simulationTimer = nil
        DiagnosticsLog.shared.append(.info, String(localized: "模拟信号丢失（不再喂样本）"))
    }

    private func feedSimulated() {
        guard let rssi = simulatedRSSI, rssi > -127 else { return }
        let identifier = settings.boundWatchID.flatMap(UUID.init(uuidString:)) ?? simulationIdentifier
        handleRSSI(identifier: identifier, rssi: rssi, date: Date())
    }

    func refreshConfig() {
        engine.config = settings.proximityConfig
        scanner.boundIdentifier = settings.boundWatchID.flatMap(UUID.init(uuidString:))
        scanner.auxiliaryIdentifiers = auxiliaryIdentifierSet()
        fusionEvidence.keepOnly(Set(settings.auxiliaryDevices.map(\.id)))
        // 暂停或关闭时切到间歇扫描，降低耗电（FR-12）。
        scanner.setMode(settings.isEnabled && !settings.isPaused ? .continuous : .lowPower)
        activity.setRequired(isRunning && settings.isEnabled && !settings.isPaused)
        bluetoothState = scanner.bluetoothState
        scannerMessage = scanner.lastError
        if settings.isPaused {
            updateStatus(.paused)
        } else if !settings.isEnabled {
            updateStatus(.disabled)
        } else if status == .paused || status == .disabled {
            updateStatus(engine.status)
        }
    }

    private func startHousekeeping() {
        housekeepingTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.housekeeping() }
        }
        RunLoop.main.add(timer, forMode: .common)
        housekeepingTimer = timer
    }

    // MARK: - 锁定闸门（规则见 `LockGate`）

    /// 监听是否处于「会产生锁定」的活跃状态；不活跃时所有待处理动作都应放弃。
    private var isMonitoringActive: Bool {
        isRunning && settings.isEnabled && !settings.isPaused
            && !monitor.isSystemSleeping && !monitor.isScreenLocked && !bluetoothOutageActive
    }

    /// 1 秒一次：条件不再满足时放弃待处理动作，否则让闸门结算（会议结束补锁 / 空闲后重新布防）。
    private func driveLockGate() {
        guard isMonitoringActive else {
            lockGate.cancel()
            syncLockDeferralNote()
            return
        }
        if let grant = lockGate.tick(watchIsFar: engine.status == .far) {
            performLock(reason: grant.reason, kind: grant.isRearm ? .rearm : .automatic)
        }
        syncLockDeferralNote()
    }

    private func syncLockDeferralNote() {
        let note = lockGate.deferralNote
        if note != lockDeferralNote { lockDeferralNote = note }
    }

    /// 状态机要求锁屏：先过会议 / 演示闸门，再执行锁定。
    private func requestLock(reason: String) {
        if let grant = lockGate.request(reason: reason) {
            performLock(reason: grant.reason, kind: grant.isRearm ? .rearm : .automatic)
        }
        syncLockDeferralNote()
    }

    // MARK: - 辅助信号源（规则见 `PresenceFusion`）

    private func auxiliaryIdentifierSet() -> Set<UUID> {
        Set(settings.auxiliaryDevices.compactMap { UUID(uuidString: $0.id) })
    }

    private func nearAuxiliaryIDs(now: Date) -> [String] {
        fusionEvidence.nearIDs(now: now, config: settings.fusionConfig)
    }

    private func auxiliaryNames(for ids: [String]) -> String {
        let names = ids.compactMap { id in settings.auxiliaryDevices.first { $0.id == id }?.displayName }
        return names.prefix(2).joined(separator: "、")
    }

    /// 手表回到身边、暂停 / 关闭、睡眠、屏幕已锁定：放弃暂缓。
    private func cancelFusionHold() {
        guard fusionHold.isHolding else { return }
        fusionHold.cancel()
        syncFusionNote()
    }

    private func syncFusionNote() {
        let note: String? = fusionHold.isHolding
            ? String(localized: "手表信号暂时丢失，\(auxiliaryNames(for: fusionHold.holders))在附近，已暂缓锁定")
            : nil
        if note != fusionNote { fusionNote = note }
    }

    /// 状态机刚判定「已离开」。返回 `true` 表示被辅助设备暂缓（调用方不要锁屏）。
    private func holdForAuxiliary(reason: ProximityEngine.FarReason) -> Bool {
        // 暂停 / 睡眠 / 已锁屏时本来就不会锁定，没必要进入暂缓。
        guard isMonitoringActive else { return false }
        let now = Date()
        let config = settings.fusionConfig
        guard fusionHold.request(reason: reason, nearIDs: nearAuxiliaryIDs(now: now), now: now, config: config) else {
            return false
        }
        let minutes = Int(config.maxHold / 60)
        DiagnosticsLog.shared.append(
            .info,
            String(localized: "手表信号丢失，但辅助设备（\(auxiliaryNames(for: fusionHold.holders))）在附近，暂缓锁定，最多 \(minutes) 分钟")
        )
        syncFusionNote()
        return true
    }

    /// 1 秒一次：结算辅助设备的暂缓。
    private func driveFusion() {
        guard isMonitoringActive else {
            cancelFusionHold()
            return
        }
        let now = Date()
        let watch = PresenceFusion.WatchView(
            isFar: engine.status == .far,
            lastSampleAt: engine.lastSample?.date,
            smoothedRSSI: engine.lastSample?.smoothedRSSI,
            farRSSI: settings.farRSSI
        )
        let result = fusionHold.tick(
            now: now,
            config: settings.fusionConfig,
            nearIDs: nearAuxiliaryIDs(now: now),
            watch: watch
        )
        switch result {
        case .idle, .holding:
            break
        case .cancelled:
            DiagnosticsLog.shared.append(.info, String(localized: "手表信号恢复，取消暂缓"))
        case .release(let release, let reason):
            let note: String
            switch release {
            case .auxiliaryGone: note = String(localized: "辅助设备已不在附近")
            case .watchConfirmedFar: note = String(localized: "手表重新出现且信号很弱")
            case .capped: note = String(localized: "已暂缓满上限")
            case .disabled: note = String(localized: "辅助设备功能已关闭")
            }
            DiagnosticsLog.shared.append(.info, String(localized: "结束暂缓：\(note)"))
            requestLock(reason: "\(reason.title)（\(note)）")
        }
        syncFusionNote()
    }

    /// 辅助设备的蓝牙地址轮换后尝试续接（每 10 秒一次）。续不上就不再提供证据，不影响锁定。
    private func rebindAuxiliaryDevices(now: Date) {
        guard now.timeIntervalSince(lastAuxiliaryRebindAt) >= 10, !settings.auxiliaryDevices.isEmpty else { return }
        lastAuxiliaryRebindAt = now

        var devices = settings.auxiliaryDevices
        var taken = Set(devices.map(\.id))
        if let bound = settings.boundWatchID { taken.insert(bound) }
        let discovered = Array(scanner.allDevices.values)
        var changed = false

        for index in devices.indices {
            let device = devices[index]
            // 还在被看到就不用续接。
            if let seen = scanner.allDevices[UUID(uuidString: device.id) ?? UUID()],
               now.timeIntervalSince(seen.lastSeen) < 60 { continue }
            guard let target = PresenceFusion.rebindTarget(for: device, among: discovered, taken: taken) else { continue }
            fusionEvidence.move(from: device.id, to: target.id.uuidString)
            devices[index].id = target.id.uuidString
            settings.moveDeviceOverride(from: device.id, to: target.id.uuidString)
            taken.insert(target.id.uuidString)
            changed = true
            DiagnosticsLog.shared.append(.info, String(localized: "辅助设备蓝牙地址已轮换，自动续接（\(device.displayName)）"))
        }
        if changed {
            settings.auxiliaryDevices = devices
            scanner.auxiliaryIdentifiers = auxiliaryIdentifierSet()
        }
    }

    // MARK: - 信任场所（规则见 `TrustedPlace`）

    /// 3 秒一次：探测网络环境，进入 / 离开已保存的场所时切换暂停。
    private func driveTrustedPlace(now: Date) {
        guard now.timeIntervalSince(lastPlaceProbeAt) >= placeProbeInterval else { return }
        lastPlaceProbeAt = now
        applyTrustedPlace(trustedPlaces.update(
            places: settings.trustedPlaces,
            enabled: settings.trustedPlaceEnabled,
            now: now
        ))
    }

    private func applyTrustedPlace(_ change: TrustedPlace.Tracker.Change) {
        let wasActive = settings.activeTrustedPlaceName != nil
        let name = trustedPlaces.current?.name
        if settings.activeTrustedPlaceName != name { settings.activeTrustedPlaceName = name }

        var resumed = false
        switch change {
        case .none:
            // 用户关闭功能 / 删除了当前场所：同样是「不再因场所而暂停」，要做同样的收尾。
            guard wasActive, name == nil else { return }
            resumed = true
            DiagnosticsLog.shared.append(.info, String(localized: "信任场所已停用，恢复自动锁定"))
        case .entered(let place):
            DiagnosticsLog.shared.append(.info, String(localized: "进入信任场所「\(place.name)」，暂停自动锁定"))
        case .left:
            resumed = true
            DiagnosticsLog.shared.append(.info, String(localized: "离开信任场所，恢复自动锁定"))
        }

        if resumed {
            settings.trustedPlaceOverridden = false
            // 暂停期间状态机没有被喂样本，状态已过时：清掉，让恢复后的第一批样本重新判定
            // （否则它可能停在过时的「已离开」上，真的离开时不会再触发锁定）。
            engine.reset()
            cancelFusionHold()
            updateStatus(.unknown)
        }
        refreshConfig()
    }

    /// 配置变化（关闭功能 / 删除场所）后立即同步，不等下一次探测。
    func syncTrustedPlaceNow() {
        lastPlaceProbeAt = Date()
        applyTrustedPlace(trustedPlaces.update(
            places: settings.trustedPlaces,
            enabled: settings.trustedPlaceEnabled
        ))
    }

    /// 把当前网络保存为信任场所。返回保存结果，失败原因由调用方展示。
    @discardableResult
    func saveCurrentNetworkAsTrustedPlace(name: String? = nil) -> TrustedPlace.SaveCheck {
        let snapshot = trustedPlaces.refreshSnapshot()
        let check = TrustedPlace.canSave(snapshot, existing: settings.trustedPlaces)
        guard check == .ok,
              let place = TrustedPlace.makePlace(
                  from: snapshot,
                  name: name,
                  fallbackName: String(localized: "当前网络")
              ) else { return check }
        settings.trustedPlaces.append(place)
        DiagnosticsLog.shared.append(.info, String(localized: "已保存信任场所「\(place.name)」"))
        syncTrustedPlaceNow()
        return .ok
    }

    /// 把当前位置保存为信任场所。失败原因由调用方展示。
    @discardableResult
    func saveCurrentLocationAsTrustedPlace(name: String? = nil, radius: Double) -> TrustedPlace.LocationSaveCheck {
        trustedPlaces.refreshSnapshot()
        let fix = trustedPlaces.snapshot.location
        let check = TrustedPlace.canSaveLocation(fix, radius: radius, existing: settings.trustedPlaces)
        guard check == .ok, let fix else { return check }
        let place = TrustedPlace.makeLocationPlace(
            from: fix,
            name: name,
            radius: radius,
            fallbackName: String(localized: "当前位置")
        )
        settings.trustedPlaces.append(place)
        DiagnosticsLog.shared.append(.info, String(localized: "已保存位置场所「\(place.name)」（半径 \(Int(radius)) 米）"))
        syncTrustedPlaceNow()
        return .ok
    }

    func removeTrustedPlace(id: UUID) {
        guard let place = settings.trustedPlaces.first(where: { $0.id == id }) else { return }
        settings.trustedPlaces.removeAll { $0.id == id }
        DiagnosticsLog.shared.append(.info, String(localized: "已删除信任场所「\(place.name)」"))
        syncTrustedPlaceNow()
    }

    // MARK: - 辅助设备管理

    /// 附近可选作辅助设备的候选：最近 30 秒内有有效信号、不是已绑定手表、尚未添加。
    /// 入选后保持稳定（规则见 `BindingListTracker`），由 housekeeping 每秒刷新。
    var auxiliaryCandidates: [DiscoveredWatch] { auxiliaryCandidateList }

    /// 辅助设备候选池：还没被选中、不是已绑定手表、近期有有效信号。
    private func auxiliaryPool(now: Date) -> [DiscoveredWatch] {
        let chosen = Set(settings.auxiliaryDevices.map(\.id))
        return scanner.allDevices.values.filter { device in
            device.rssi < 0
                && now.timeIntervalSince(device.lastSeen) <= 30
                && device.id.uuidString != settings.boundWatchID
                && !chosen.contains(device.id.uuidString)
        }
    }

    private func refreshAuxiliaryCandidates(now: Date) {
        auxiliaryTracker.update(strong: [], all: auxiliaryPool(now: now), now: now)
        // 有名字的优先：无名广播地址一轮换就无法续接，价值低。
        // 对已稳定的顺序做稳定分区，不引入新的跳动。
        let ordered = auxiliaryTracker.visible
        auxiliaryCandidateList = ordered.filter { !$0.name.isEmpty } + ordered.filter { $0.name.isEmpty }
    }

    func addAuxiliaryDevice(_ device: DiscoveredWatch) {
        guard settings.auxiliaryDevices.count < PresenceFusion.maxDevices,
              device.id.uuidString != settings.boundWatchID,
              !settings.auxiliaryDevices.contains(where: { $0.id == device.id.uuidString }) else { return }
        let entry = AuxiliaryDevice(
            id: device.id.uuidString,
            name: device.name,
            advertisement: AppleAdvertisement.parse(device.manufacturerData)?.fingerprint,
            airPodsModel: device.airPodsModel
        )
        settings.auxiliaryDevices.append(entry)
        scanner.auxiliaryIdentifiers = auxiliaryIdentifierSet()
        DiagnosticsLog.shared.append(.info, String(localized: "已添加辅助设备：\(entry.displayName)"))
    }

    func removeAuxiliaryDevice(id: String) {
        guard let entry = settings.auxiliaryDevices.first(where: { $0.id == id }) else { return }
        settings.auxiliaryDevices.removeAll { $0.id == id }
        fusionEvidence.keepOnly(Set(settings.auxiliaryDevices.map(\.id)))
        scanner.auxiliaryIdentifiers = auxiliaryIdentifierSet()
        DiagnosticsLog.shared.append(.info, String(localized: "已移除辅助设备：\(entry.displayName)"))
    }

    /// 辅助设备此刻是否有「在附近」的证据，供设置页展示。
    func isAuxiliaryNear(id: String) -> Bool {
        fusionEvidence.nearIDs(now: Date(), config: settings.fusionConfig).contains(id)
    }

    /// 最近一次读数（窗口内最强），供设置页展示。
    func auxiliaryRSSI(id: String) -> Int? {
        fusionEvidence.bestRSSI(id: id, now: Date(), window: settings.fusionConfig.freshness)
    }

    // MARK: - 蓝牙不可用期间（规则见 `BluetoothOutage`）

    private var bluetoothOutageActive = false

    private func syncBluetoothAvailability() {
        let state = scanner.bluetoothState
        switch BluetoothOutage.transition(wasUnavailable: bluetoothOutageActive, state: state) {
        case .none:
            return
        case .began:
            bluetoothOutageActive = true
            DiagnosticsLog.shared.append(.warning, String(localized: "蓝牙不可用（\(state.title)），暂停信号丢失结算"))
            // 蓝牙不可用不等于手表离开：停掉状态机，避免约 20 秒后按「信号丢失」误锁。
            engine.stop()
            engine.reset()
            unlocker.cancelPendingApproach()
            if settings.isEnabled, !settings.isPaused { updateStatus(.unknown) }
            if settings.notificationsEnabled, settings.boundWatchID != nil, settings.isEnabled, !settings.isPaused {
                NotificationPresenter.shared.notify(
                    title: String(localized: "蓝牙不可用"),
                    body: BluetoothOutage.notificationBody(for: state),
                    reason: .bluetoothIssue
                )
            }
        case .ended:
            bluetoothOutageActive = false
            wakeGraceUntil = Date().addingTimeInterval(settings.unlockGraceAfterWake)
            DiagnosticsLog.shared.append(.info, String(localized: "蓝牙已恢复，重置状态并进入宽限期"))
            if isRunning, !monitor.isSystemSleeping { engine.start() }
        }
    }

    private func housekeeping() {
        bluetoothState = scanner.bluetoothState
        scannerMessage = scanner.lastError
        syncBluetoothAvailability()
        let housekeepingNow = Date()
        driveTrustedPlace(now: housekeepingNow)
        rebindAuxiliaryDevices(now: housekeepingNow)
        upgradeBoundNameSnapshot()
        refreshBindingList()
        driveFusion()
        driveLockGate()

        // 绑定后自动校准的收尾（手表长时间没有广播时也要结算）。
        if let deadline = bindCalibrationDeadline, Date() > deadline {
            finishBindCalibration()
        }

        // 误锁反馈入口只在自动锁定后的 10 分钟内可用。
        if let last = lastAutoLockAt {
            let available = Date().timeIntervalSince(last) <= falseLockReportWindow
            if available != falseLockFeedbackAvailable { falseLockFeedbackAvailable = available }
        } else if falseLockFeedbackAvailable {
            falseLockFeedbackAvailable = false
        }

        // FR-06：暂停到期后自动恢复（UserDefaults 不会主动发出变更通知）。
        if status == .paused && !settings.isPaused {
            DiagnosticsLog.shared.append(.info, String(localized: "暂停已到期，自动恢复自动锁定"))
            refreshConfig()
        }

        // FR-02：超过 30 分钟未出现的外设移出候选列表。
        let now = Date()
        guard now.timeIntervalSince(lastPruneAt) >= 60 else { return }
        lastPruneAt = now
        let before = scanner.candidates.count
        scanner.prune(olderThan: candidateTTL)
        let removed = before - scanner.candidates.count
        if removed > 0 {
            DiagnosticsLog.shared.append(.info, String(localized: "清理 \(removed) 个长时间未出现的候选设备"))
        }
    }

    func bind(watch: DiscoveredWatch) {
        settings.boundWatchID = watch.id.uuidString
        // 绑定那一刻的名称快照：之后广播里的名称时有时无，界面一律优先用它（见 `DeviceNaming.resolve`）。
        // 无名广播很常见，没有名称时用 AirPods 型号，再不行用 ID 前 8 位当可读名字。
        settings.boundWatchName = DeviceNaming.snapshotName(
            name: watch.name,
            model: watch.airPodsModel,
            id: watch.id.uuidString
        )
        // 记录广播类型指纹：地址轮换后用它校验「还是同一类广播」，比只比对名称更可靠。
        settings.boundWatchAdvertisement = AppleAdvertisement.parse(watch.manufacturerData)?.fingerprint
        scanner.boundIdentifier = watch.id
        engine.reset()
        DiagnosticsLog.shared.append(.info, String(localized: "已绑定手表：\(watch.displayName)"))
        startBindCalibration()
    }

    // MARK: - 绑定后的自动校准
    //
    // 默认阈值（-55 / -70）是按信号较强的设备取的，而 Apple 设备的广播功率与调度由系统控制，
    // 第三方只能拿到 RSSI，实测值普遍比默认阈值更低（桌前约 -70 ~ -85，该区间仍待真机确认）。
    // 绑定那一刻手表一定在手边，直接用这段采样作为「在身边」基准最省事。

    private let bindCalibrationWindow: TimeInterval = 10
    private let bindCalibrationMinimumSamples = 5
    private let bindCalibrationTargetSamples = 10
    private var bindCalibrationSamples: [Int] = []
    private var bindCalibrationDeadline: Date?

    private func startBindCalibration() {
        bindCalibrationSamples = []
        bindCalibrationDeadline = Date().addingTimeInterval(bindCalibrationWindow)
        tuningMessage = String(localized: "绑定后自动校准中：请让手表保持在身边约 10 秒")
        DiagnosticsLog.shared.append(.info, String(localized: "开始绑定后自动校准（10 秒）"))
    }

    private func collectBindCalibrationSample(rssi: Int, date: Date) {
        guard let deadline = bindCalibrationDeadline else { return }
        guard date <= deadline else {
            finishBindCalibration()
            return
        }
        bindCalibrationSamples.append(rssi)
        if bindCalibrationSamples.count >= bindCalibrationTargetSamples {
            finishBindCalibration()
        }
    }

    private func finishBindCalibration() {
        bindCalibrationDeadline = nil
        let samples = bindCalibrationSamples
        bindCalibrationSamples = []

        guard samples.count >= bindCalibrationMinimumSamples else {
            DiagnosticsLog.shared.append(.warning, String(localized: "绑定后自动校准样本不足（\(samples.count) 个），保留原阈值"))
            tuningMessage = String(localized: "自动校准样本不足，可在「高级 → 距离校准向导」手动校准")
            return
        }

        let result = DistanceCalibrator.autoThresholds(
            from: samples,
            fallback: .init(
                nearRSSI: settings.nearRSSI,
                farRSSI: settings.farRSSI,
                measuredPower: settings.measuredPower
            )
        )
        settings.applyAutoCalibration(result)
        refreshConfig()

        let message = String(localized: "已按绑定时的信号自动校准：1 米标定 \(result.measuredPower)、在身边 \(result.nearRSSI)、已离开 \(result.farRSSI) dBm（\(samples.count) 个样本）")
        tuningMessage = message
        DiagnosticsLog.shared.append(.info, message)
    }

    func unbindWatch() {
        settings.boundWatchID = nil
        settings.boundWatchName = nil
        scanner.boundIdentifier = nil
        engine.reset()
        updateStatus(.unknown)
    }

    func pause(minutes: Double) {
        settings.pause(minutes: minutes)
        updateStatus(.paused)
    }

    func resume() {
        settings.resume()
        // 在信任场所内点「恢复」：这次直接恢复锁定，直到离开该场所（再次进入时重新生效）。
        if settings.isTrustedPlacePausing { settings.trustedPlaceOverridden = true }
        refreshConfig()
        updateStatus(engine.status)
    }

    /// 菜单栏中的「立即锁定」。
    func lockNow() {
        performLock(reason: String(localized: "手动锁定"), kind: .manual)
    }

    /// 用户反馈「刚才这次是误锁」，触发自动调参（M3）。
    func reportFalseLock(now: Date = Date()) {
        guard let last = lastAutoLockAt, now.timeIntervalSince(last) <= falseLockReportWindow else {
            DiagnosticsLog.shared.append(.warning, String(localized: "没有可反馈的自动锁定，忽略误锁反馈"))
            return
        }
        // 同一次锁定只能反馈一次：否则连点「记为误锁」会把误锁率越刷越高，触发不该有的自动放宽。
        lockHistory.markLatestAutomaticAsFalse(now: now, window: falseLockReportWindow)
        lastAutoLockAt = nil
        falseLockFeedbackAvailable = false
        guard let suggestion = settings.recordFalseLock() else {
            tuningMessage = String(localized: "已记录误锁反馈，当前误锁率未超阈值，暂不调整")
            DiagnosticsLog.shared.append(.info, String(localized: "记录误锁反馈（暂不调整阈值）"))
            return
        }
        let before = settings.currentFarThresholds
        settings.applyTuned(suggestion)
        refreshConfig()
        tuningMessage = String(localized: "已记录误锁反馈：已离开 \(before.farRSSI) → \(suggestion.farRSSI) dBm，等待 \(Int(before.farDwell)) → \(Int(suggestion.farDwell)) 秒")
        DiagnosticsLog.shared.append(.info, String(localized: "误锁反馈触发自动调参：\(tuningMessage ?? "")"))
    }

    /// 恢复默认阈值并清空调参样本。
    func resetTuning() {
        settings.resetTuningStats()
        settings.applyTuned(SettingsStore.defaultFarThresholds)
        refreshConfig()
        tuningMessage = String(localized: "已恢复默认阈值")
        DiagnosticsLog.shared.append(.info, String(localized: "恢复默认阈值并清空调参样本"))
    }

    private let falseLockReportWindow: TimeInterval = 10 * 60

    func visibleCandidates() -> [DiscoveredWatch] {
        scanner.candidates.values.sorted { lhs, rhs in
            if let bound = settings.boundWatchID {
                if lhs.id.uuidString == bound { return true }
                if rhs.id.uuidString == bound { return false }
            }
            return lhs.rssi > rhs.rssi
        }
    }

    /// 所有被发现的 BLE 设备（含未匹配），供绑定页调试「搜不到手表」。
    func allDiscoveredDevices() -> [DiscoveredWatch] {
        scanner.allDevices.values.sorted(by: DiscoveredWatch.isRankedBefore)
    }

    /// 绑定列表数据源：强候选 + 信号最强的若干台，入选后保持稳定（规则见 `BindingListTracker`）。
    ///
    /// Apple 的邻近广播基本都是无名广播，名称匹配（是否含 watch）并不可靠，
    /// 因此这里不强依赖识别规则：把手表贴近 Mac 时它必然是信号最强的设备之一，
    /// 由用户从「离你最近」的几台里点选，绑定后按 identifier 精确追踪。
    ///
    /// 列表由 housekeeping 每秒刷新一次，而不是每次界面重绘都重新计算：
    /// 否则列表内容取决于重绘时机，行会随信号抖动来回跳。
    var bindingCandidates: [DiscoveredWatch] { bindingList }

    private func refreshBindingList() {
        bindingTracker.update(
            strong: visibleCandidates(),
            all: allDiscoveredDevices(),
            now: Date()
        )
        bindingList = bindingTracker.visible

        let now = Date()
        refreshAuxiliaryCandidates(now: now)
        allDevicesTracker.update(strong: [], all: allDiscoveredDevices(), now: now)
        allDevicesList = allDevicesTracker.visible
    }

    /// 「显示全部」用的稳定列表（引导页）。诊断页要看原始快照，仍用 `allDiscoveredDevices()`。
    var stableAllDevices: [DiscoveredWatch] { allDevicesList }

    // MARK: - 设备名称 / 图标（规则见 `DeviceNaming`）

    /// 设备在界面上的名称与图标：已绑定 / 已选为辅助的设备优先用快照名，再叠加用户的手动覆盖。
    func label(for device: DiscoveredWatch) -> DeviceLabel {
        let id = device.id.uuidString
        let isBound = id == settings.boundWatchID
        let auxiliary = settings.auxiliaryDevices.first { $0.id == id }
        return DeviceNaming.resolve(
            id: id,
            liveName: device.name,
            model: device.airPodsModel,
            snapshotName: isBound ? settings.boundWatchName : auxiliary?.name,
            snapshotModel: auxiliary?.airPodsModel,
            override: settings.deviceOverrides[id],
            fallbackKind: isBound ? .watch : .unknown
        )
    }

    /// 已选辅助设备的名称与图标：实时广播暂时拿不到名称时，用添加时的快照。
    func label(forAuxiliary device: AuxiliaryDevice) -> DeviceLabel {
        let live = UUID(uuidString: device.id).flatMap { scanner.allDevices[$0] }
        return DeviceNaming.resolve(
            id: device.id,
            liveName: live?.name ?? "",
            model: live?.airPodsModel,
            snapshotName: device.name,
            snapshotModel: device.airPodsModel,
            override: settings.deviceOverrides[device.id]
        )
    }

    /// 已绑定设备的名称与图标；未绑定时为 nil。
    func boundDeviceLabel() -> DeviceLabel? {
        guard let id = settings.boundWatchID else { return nil }
        let live = UUID(uuidString: id).flatMap { scanner.allDevices[$0] }
        return DeviceNaming.resolve(
            id: id,
            liveName: live?.name ?? "",
            model: live?.airPodsModel,
            snapshotName: settings.boundWatchName,
            override: settings.deviceOverrides[id],
            fallbackKind: .watch
        )
    }

    func setDeviceOverride(_ override: DeviceOverride?, for id: String) {
        settings.setDeviceOverride(override, for: id)
    }

    /// 绑定时设备没有名称（快照是占位名），之后一旦广播里出现真实名称就补上。
    /// 只升级占位名，不改动已有的真实快照，否则「快照优先」就失去意义。
    private func upgradeBoundNameSnapshot() {
        guard let id = settings.boundWatchID,
              let uuid = UUID(uuidString: id),
              let live = scanner.allDevices[uuid], !live.name.isEmpty else { return }
        let current = settings.boundWatchName
        guard current == nil || current.map({ DeviceNaming.isPlaceholder($0, id: id) }) == true else { return }
        settings.boundWatchName = live.name
    }

    // MARK: - 内部处理

    private func handleRSSI(identifier: UUID, rssi: Int, date: Date) {
        // 仅已绑定设备的信号参与判定，也不更新「最后更新」时间；未绑定时一律忽略。
        guard matchesBoundWatch(identifier) else { return }
        lastSeen = date
        collectBindCalibrationSample(rssi: rssi, date: date)
        bluetoothState = scanner.bluetoothState
        scannerMessage = scanner.lastError

        guard settings.isEnabled, !settings.isPaused else {
            updateStatus(settings.isPaused ? .paused : .disabled)
            return
        }
        engine.update(rssi: rssi, at: date)
        updateStatus(engine.status)
        if isRunning, !monitor.isSystemSleeping, engine.status == .near {
            unlocker.retryPendingApproach(now: date)
        }
    }

    private var lastPresenceLogAt: Date = .distantPast

    /// 广播在、但没有有效信号强度时按「在场」处理，并限流记一条日志（避免刷屏）。
    private func logPresenceWithoutRSSI() {
        let now = Date()
        guard now.timeIntervalSince(lastPresenceLogAt) > 300 else { return }
        lastPresenceLogAt = now
        DiagnosticsLog.shared.append(
            .warning,
            String(localized: "收到手表广播但系统未提供有效信号强度（RSSI=127），已按「手表仍在场」处理，不会因此锁定")
        )
    }

    /// 判断样本是否来自已绑定手表；若只是蓝牙地址轮换（RPA）导致 ID 变化，则自动续接绑定。
    private func matchesBoundWatch(_ identifier: UUID) -> Bool {
        // 模拟信号使用专用标识（真实广播在模拟期间已被忽略），未绑定时也要能走通调试流程。
        if identifier == simulationIdentifier, simulatedRSSI != nil { return true }
        // 未绑定时不接受任何真实设备：否则邻居的 Apple 设备也能驱动本机锁屏 / 亮屏。
        guard let bound = settings.boundWatchID else { return false }
        if WatchMatcher.isBoundSample(boundIdentifier: bound, sampleIdentifier: identifier) { return true }

        guard let device = scanner.candidates[identifier],
              WatchMatcher.shouldRebind(
                  boundIdentifier: bound,
                  boundName: settings.boundWatchName,
                  candidateIdentifier: identifier,
                  candidateName: device.name,
                  boundAdvertisement: settings.boundWatchAdvertisement,
                  candidateManufacturerData: device.manufacturerData
              ) else { return false }

        settings.moveDeviceOverride(from: bound, to: identifier.uuidString)
        settings.boundWatchID = identifier.uuidString
        settings.boundWatchName = device.name
        settings.boundWatchAdvertisement = AppleAdvertisement.parse(device.manufacturerData)?.fingerprint
        scanner.boundIdentifier = identifier
        DiagnosticsLog.shared.append(.info, String(localized: "手表蓝牙地址已轮换，自动续接绑定（\(device.displayName)）"))
        return true
    }

    private func handle(event: ProximityEngine.Event) {
        switch event {
        case .becameFar(let reason):
            unlocker.cancelPendingApproach()
            // 手表只是「没广播」时，附近有辅助设备就先别锁（手表明确很弱时不会暂缓）。
            if holdForAuxiliary(reason: reason) { return }
            requestLock(reason: reason.title)
        case .becameNear:
            lockGate.cancel()
            cancelFusionHold()
            syncLockDeferralNote()
            guard isRunning, !monitor.isSystemSleeping else { return }
            // 锁屏不阻止显示器唤醒；显示器亮起与会话解锁分别由 monitor 跟踪。
            unlocker.handleApproach()
        }
    }

    private func performLock(reason: String, kind: LockHistory.Record.Kind = .automatic) {
        guard settings.isEnabled, !settings.isPaused else {
            DiagnosticsLog.shared.append(.warning, String(localized: "已暂停或已关闭，跳过锁定：\(reason)"))
            return
        }
        guard Date() >= wakeGraceUntil else {
            DiagnosticsLog.shared.append(.info, String(localized: "处于唤醒宽限期，跳过锁定"))
            return
        }
        guard !monitor.refreshSessionLockState() else {
            DiagnosticsLog.shared.append(.info, String(localized: "屏幕已锁定，跳过本次锁定"))
            return
        }
        let locker = ScreenLocker(method: settings.lockMethod, customCommand: settings.customLockCommand)
        let detail = String(format: String(localized: "RSSI %.0f dBm，约 %.1f 米"), smoothedRSSI, estimatedDistance)
        DiagnosticsLog.shared.append(.info, String(localized: "触发锁定：\(reason)（\(detail)）"))
        // 缺权限时锁屏一定会失败：直接告诉用户去哪授权，而不是只在诊断日志里留一行晦涩的报错。
        if let issue = locker.permissionIssue() {
            DiagnosticsLog.shared.append(.error, String(localized: "无法锁定：\(issue)"))
            if settings.notificationsEnabled {
                NotificationPresenter.shared.notify(
                    title: String(localized: "无法锁定 Mac"),
                    body: locker.permissionIssueNotificationBody,
                    reason: .lockBlocked
                )
            }
            return
        }
        guard locker.lock() else { return }
        lastLockReason = reason
        lastLockAt = Date()
        let reading = LockHistory.reading(rssi: smoothedRSSI, distance: estimatedDistance)
        lockHistory.record(.init(
            date: Date(),
            kind: kind,
            reason: reason,
            rssi: reading.rssi,
            distance: reading.distance
        ))

        if kind == .automatic {
            settings.recordAutoLock()
            lastAutoLockAt = Date()
            tuningMessage = nil
            falseLockFeedbackAvailable = true
        }
        if settings.notificationsEnabled {
            NotificationPresenter.shared.notify(
                title: String(localized: "已锁定 Mac"),
                body: "\(reason)（\(detail)）",
                reason: .locked
            )
        }
    }

    private func updateStatus(_ newStatus: ProximityStatus) {
        guard status != newStatus else { return }
        status = newStatus
    }
}
