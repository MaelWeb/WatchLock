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

    /// 菜单栏提示：自动锁定因会议 / 演示被暂缓。
    @Published private(set) var lockDeferralNote: String?

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
    private var lastPruneAt: Date = .distantPast
    private let candidateTTL: TimeInterval = 30 * 60

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
                self.updateStatus(.unknown)
                self.engine.start()
                self.scanner.start()
                DiagnosticsLog.shared.append(.info, "系统唤醒，进入宽限期并恢复扫描")
            }
        }
        monitor.onSleep = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                DiagnosticsLog.shared.append(.info, "系统进入睡眠，暂停蓝牙扫描")
                self.unlocker.cancelPendingApproach()
                self.scanner.stop()
                self.engine.stop()
            }
        }
        monitor.onScreenLocked = { [weak self] in
            Task { @MainActor in
                self?.lockGate.cancel()
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
        DiagnosticsLog.shared.append(.info, "开始监听手表距离")
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
        DiagnosticsLog.shared.append(.info, "开始模拟信号：\(rssi) dBm")
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
        DiagnosticsLog.shared.append(.info, "停止模拟信号")
    }

    /// 模拟「手表离开后彻底失联」：停止注入且不再接收真实广播，用于验证 signalLostTimeout。
    func simulateSignalLoss() {
        simulatedRSSI = -127
        simulationTimer?.invalidate()
        simulationTimer = nil
        DiagnosticsLog.shared.append(.info, "模拟信号丢失（不再喂样本）")
    }

    private func feedSimulated() {
        guard let rssi = simulatedRSSI, rssi > -127 else { return }
        let identifier = settings.boundWatchID.flatMap(UUID.init(uuidString:)) ?? simulationIdentifier
        handleRSSI(identifier: identifier, rssi: rssi, date: Date())
    }

    func refreshConfig() {
        engine.config = settings.proximityConfig
        scanner.boundIdentifier = settings.boundWatchID.flatMap(UUID.init(uuidString:))
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

    /// 1 秒一次：条件不再满足时放弃待处理动作，否则让闸门结算（会议结束补锁 / 空闲后重新布防）。
    private func driveLockGate() {
        let active = isRunning && settings.isEnabled && !settings.isPaused
            && !monitor.isSystemSleeping && !monitor.isScreenLocked && !bluetoothOutageActive
        guard active else {
            lockGate.cancel()
            syncLockDeferralNote()
            return
        }
        if let grant = lockGate.tick(watchIsFar: engine.status == .far) {
            performLock(reason: grant.reason, isAutomatic: !grant.isRearm)
        }
        syncLockDeferralNote()
    }

    private func syncLockDeferralNote() {
        let note = lockGate.deferralNote
        if note != lockDeferralNote { lockDeferralNote = note }
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
            DiagnosticsLog.shared.append(.warning, "蓝牙不可用（\(state.title)），暂停信号丢失结算")
            // 蓝牙不可用不等于手表离开：停掉状态机，避免约 20 秒后按「信号丢失」误锁。
            engine.stop()
            engine.reset()
            unlocker.cancelPendingApproach()
            if settings.isEnabled, !settings.isPaused { updateStatus(.unknown) }
            if settings.notificationsEnabled, settings.boundWatchID != nil, settings.isEnabled, !settings.isPaused {
                NotificationPresenter.shared.notify(
                    title: "蓝牙不可用",
                    body: BluetoothOutage.notificationBody(for: state),
                    reason: .bluetoothIssue
                )
            }
        case .ended:
            bluetoothOutageActive = false
            wakeGraceUntil = Date().addingTimeInterval(settings.unlockGraceAfterWake)
            DiagnosticsLog.shared.append(.info, "蓝牙已恢复，重置状态并进入宽限期")
            if isRunning, !monitor.isSystemSleeping { engine.start() }
        }
    }

    private func housekeeping() {
        bluetoothState = scanner.bluetoothState
        scannerMessage = scanner.lastError
        syncBluetoothAvailability()
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
            DiagnosticsLog.shared.append(.info, "暂停已到期，自动恢复自动锁定")
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
            DiagnosticsLog.shared.append(.info, "清理 \(removed) 个长时间未出现的候选设备")
        }
    }

    func bind(watch: DiscoveredWatch) {
        settings.boundWatchID = watch.id.uuidString
        // 无名广播很常见，用 ID 前 8 位当可读名字。
        settings.boundWatchName = watch.name.isEmpty ? String(watch.id.uuidString.prefix(8)) : watch.name
        // 记录广播类型指纹：地址轮换后用它校验「还是同一类广播」，比只比对名称更可靠。
        settings.boundWatchAdvertisement = AppleAdvertisement.parse(watch.manufacturerData)?.fingerprint
        scanner.boundIdentifier = watch.id
        engine.reset()
        DiagnosticsLog.shared.append(.info, "已绑定手表：\(watch.displayName)")
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
        tuningMessage = "绑定后自动校准中：请让手表保持在身边约 10 秒"
        DiagnosticsLog.shared.append(.info, "开始绑定后自动校准（10 秒）")
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
            DiagnosticsLog.shared.append(.warning, "绑定后自动校准样本不足（\(samples.count) 个），保留原阈值")
            tuningMessage = "自动校准样本不足，可在「高级 → 距离校准向导」手动校准"
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

        let message = "已按绑定时的信号自动校准：1 米标定 \(result.measuredPower)、在身边 \(result.nearRSSI)、已离开 \(result.farRSSI) dBm（\(samples.count) 个样本）"
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
        updateStatus(engine.status)
    }

    /// 菜单栏中的「立即锁定」。
    func lockNow() {
        performLock(reason: "手动锁定", isAutomatic: false)
    }

    /// 用户反馈「刚才这次是误锁」，触发自动调参（M3）。
    func reportFalseLock(now: Date = Date()) {
        guard let last = lastAutoLockAt, now.timeIntervalSince(last) <= falseLockReportWindow else {
            DiagnosticsLog.shared.append(.warning, "没有可反馈的自动锁定，忽略误锁反馈")
            return
        }
        guard let suggestion = settings.recordFalseLock() else {
            tuningMessage = "已记录误锁反馈，当前误锁率未超阈值，暂不调整"
            DiagnosticsLog.shared.append(.info, "记录误锁反馈（暂不调整阈值）")
            return
        }
        let before = settings.currentFarThresholds
        settings.applyTuned(suggestion)
        refreshConfig()
        tuningMessage = "已记录误锁反馈：已离开 \(before.farRSSI) → \(suggestion.farRSSI) dBm，等待 \(Int(before.farDwell)) → \(Int(suggestion.farDwell)) 秒"
        DiagnosticsLog.shared.append(.info, "误锁反馈触发自动调参：\(tuningMessage ?? "")")
    }

    /// 恢复默认阈值并清空调参样本。
    func resetTuning() {
        settings.resetTuningStats()
        settings.applyTuned(SettingsStore.defaultFarThresholds)
        refreshConfig()
        tuningMessage = "已恢复默认阈值"
        DiagnosticsLog.shared.append(.info, "恢复默认阈值并清空调参样本")
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
        scanner.allDevices.values.sorted { $0.rssi > $1.rssi }
    }

    /// 绑定列表数据源：强候选 + 当前信号最强的若干台，按 RSSI 排序。
    ///
    /// Apple 的邻近广播基本都是无名广播，名称匹配（是否含 watch）并不可靠，
    /// 因此这里不强依赖识别规则：把手表贴近 Mac 时它必然是信号最强的设备之一，
    /// 由用户从「离你最近」的几台里点选，绑定后按 identifier 精确追踪。
    func bindingCandidates(limit: Int = 8) -> [DiscoveredWatch] {
        DiscoveredWatch.mergedBindingList(
            strong: visibleCandidates(),
            all: allDiscoveredDevices(),
            limit: limit
        )
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
            "收到手表广播但系统未提供有效信号强度（RSSI=127），已按「手表仍在场」处理，不会因此锁定"
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

        settings.boundWatchID = identifier.uuidString
        settings.boundWatchName = device.name
        settings.boundWatchAdvertisement = AppleAdvertisement.parse(device.manufacturerData)?.fingerprint
        scanner.boundIdentifier = identifier
        DiagnosticsLog.shared.append(.info, "手表蓝牙地址已轮换，自动续接绑定（\(device.displayName)）")
        return true
    }

    private func handle(event: ProximityEngine.Event) {
        switch event {
        case .becameFar(let reason):
            unlocker.cancelPendingApproach()
            if let grant = lockGate.request(reason: reason.title) {
                performLock(reason: grant.reason, isAutomatic: !grant.isRearm)
            }
            syncLockDeferralNote()
        case .becameNear:
            lockGate.cancel()
            syncLockDeferralNote()
            guard isRunning, !monitor.isSystemSleeping else { return }
            // 锁屏不阻止显示器唤醒；显示器亮起与会话解锁分别由 monitor 跟踪。
            unlocker.handleApproach()
        }
    }

    private func performLock(reason: String, isAutomatic: Bool = true) {
        guard settings.isEnabled, !settings.isPaused else {
            DiagnosticsLog.shared.append(.warning, "已暂停或已关闭，跳过锁定：\(reason)")
            return
        }
        guard Date() >= wakeGraceUntil else {
            DiagnosticsLog.shared.append(.info, "处于唤醒宽限期，跳过锁定")
            return
        }
        guard !monitor.refreshSessionLockState() else {
            DiagnosticsLog.shared.append(.info, "屏幕已锁定，跳过本次锁定")
            return
        }
        let locker = ScreenLocker(method: settings.lockMethod, customCommand: settings.customLockCommand)
        let detail = String(format: "RSSI %.0f dBm，约 %.1f 米", smoothedRSSI, estimatedDistance)
        DiagnosticsLog.shared.append(.info, "触发锁定：\(reason)（\(detail)）")
        // 缺权限时锁屏一定会失败：直接告诉用户去哪授权，而不是只在诊断日志里留一行晦涩的报错。
        if let issue = locker.permissionIssue() {
            DiagnosticsLog.shared.append(.error, "无法锁定：\(issue)")
            if settings.notificationsEnabled {
                NotificationPresenter.shared.notify(
                    title: "无法锁定 Mac",
                    body: locker.permissionIssueNotificationBody,
                    reason: .lockBlocked
                )
            }
            return
        }
        guard locker.lock() else { return }
        lastLockReason = reason
        lastLockAt = Date()

        if isAutomatic {
            settings.recordAutoLock()
            lastAutoLockAt = Date()
            tuningMessage = nil
            falseLockFeedbackAvailable = true
        }
        if settings.notificationsEnabled {
            NotificationPresenter.shared.notify(
                title: "已锁定 Mac",
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
