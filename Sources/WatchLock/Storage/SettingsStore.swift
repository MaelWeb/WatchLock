import Foundation

/// 用户设置，持久化在 UserDefaults 中。
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private enum Key {
        static let isEnabled = "settings.isEnabled"
        static let boundWatchID = "settings.boundWatchID"
        static let boundWatchName = "settings.boundWatchName"
        static let nearRSSI = "settings.nearRSSI"
        static let farRSSI = "settings.farRSSI"
        static let smoothing = "settings.smoothing"
        static let farDwell = "settings.farDwell"
        static let nearDwell = "settings.nearDwell"
        static let signalLostTimeout = "settings.signalLostTimeout"
        static let lockOnSignalLoss = "settings.lockOnSignalLoss"
        static let boundWatchAdvertisement = "settings.boundWatchAdvertisement"
        static let measuredPower = "settings.measuredPower"
        static let pathLossExponent = "settings.pathLossExponent"
        static let lockMethod = "settings.lockMethod"
        static let customLockCommand = "settings.customLockCommand"
        static let unlockStrategy = "settings.unlockStrategy"
        static let wakeDisplayOnApproach = "settings.wakeDisplayOnApproach"
        static let unlockGraceAfterWake = "settings.unlockGraceAfterWake"
        static let pauseUntil = "settings.pauseUntil"
        static let launchAtLogin = "settings.launchAtLogin"
        static let showRSSIInMenuBar = "settings.showRSSIInMenuBar"
        static let notificationsEnabled = "settings.notificationsEnabled"
        static let debugLogging = "settings.debugLogging"
        static let confirmBeforeLock = "settings.confirmBeforeLock"
        static let meetingExemptionEnabled = "settings.meetingExemptionEnabled"
        static let meetingMaxDeferralMinutes = "settings.meetingMaxDeferralMinutes"
        static let rearmAfterManualUnlock = "settings.rearmAfterManualUnlock"
        static let rearmIdleMinutes = "settings.rearmIdleMinutes"
        static let trustedPlaceEnabled = "settings.trustedPlaceEnabled"
        static let trustedPlaces = "settings.trustedPlaces"
        static let fusionEnabled = "settings.fusionEnabled"
        static let auxiliaryDevices = "settings.auxiliaryDevices"
        static let hasCompletedOnboarding = "settings.hasCompletedOnboarding"
        static let autoLockCount = "stats.autoLockCount"
        static let falseLockCount = "stats.falseLockCount"
    }

    /// 关键参数默认值，同时作为自动调参的回归目标。
    enum Defaults {
        static let farRSSI = -70
        static let farDwell: Double = 5
        static let nearRSSI = -55
        /// Apple 设备的 BLE 广播会随设备状态动态启停，12 秒太短，默认放宽到 20 秒。
        /// 依据见 `docs/anti-false-lock-research.md` 证据 2。
        static let signalLostTimeout: Double = 20
        /// 会议 / 演示豁免：最长暂缓时间（分钟）。硬上限，避免让锁屏长期失效。
        static let meetingMaxDeferralMinutes = 60
        static let meetingMaxDeferralRange = 5 ... 240
        /// 手动解锁后重新布防：键鼠空闲多久（分钟）后再锁。
        static let rearmIdleMinutes = 5
        static let rearmIdleRange = 1 ... 60
    }

    private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// 默认使用 `UserDefaults.standard`，测试时可注入独立 suite 避免污染真实设置。
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Key.isEnabled) as? Bool ?? true
        boundWatchID = defaults.string(forKey: Key.boundWatchID)
        boundWatchName = defaults.string(forKey: Key.boundWatchName)
        boundWatchAdvertisement = defaults.string(forKey: Key.boundWatchAdvertisement)
        nearRSSI = defaults.object(forKey: Key.nearRSSI) as? Int ?? Defaults.nearRSSI
        farRSSI = defaults.object(forKey: Key.farRSSI) as? Int ?? Defaults.farRSSI
        smoothing = defaults.object(forKey: Key.smoothing) as? Double ?? 0.25
        farDwell = defaults.object(forKey: Key.farDwell) as? Double ?? Defaults.farDwell
        nearDwell = defaults.object(forKey: Key.nearDwell) as? Double ?? 1
        signalLostTimeout = defaults.object(forKey: Key.signalLostTimeout) as? Double ?? Defaults.signalLostTimeout
        lockOnSignalLoss = defaults.object(forKey: Key.lockOnSignalLoss) as? Bool ?? true
        measuredPower = defaults.object(forKey: Key.measuredPower) as? Int ?? -55
        pathLossExponent = defaults.object(forKey: Key.pathLossExponent) as? Double ?? 2.5
        lockMethod = LockMethod(rawValue: defaults.string(forKey: Key.lockMethod) ?? "") ?? .controlCommandQ
        customLockCommand = defaults.string(forKey: Key.customLockCommand) ?? ""
        unlockStrategy = UnlockStrategy(rawValue: defaults.string(forKey: Key.unlockStrategy) ?? "") ?? .systemAutoUnlock
        wakeDisplayOnApproach = defaults.object(forKey: Key.wakeDisplayOnApproach) as? Bool ?? true
        unlockGraceAfterWake = defaults.object(forKey: Key.unlockGraceAfterWake) as? Double ?? 8
        let pause = defaults.object(forKey: Key.pauseUntil) as? Double ?? 0
        pauseUntil = pause > 0 ? Date(timeIntervalSince1970: pause) : nil
        launchAtLogin = defaults.object(forKey: Key.launchAtLogin) as? Bool ?? false
        // 默认只显示图标：状态已由图标形状 / 颜色表达，文字会白白占用菜单栏宽度。
        showRSSIInMenuBar = defaults.object(forKey: Key.showRSSIInMenuBar) as? Bool ?? false
        notificationsEnabled = defaults.object(forKey: Key.notificationsEnabled) as? Bool ?? true
        debugLogging = defaults.object(forKey: Key.debugLogging) as? Bool ?? false
        confirmBeforeLock = defaults.object(forKey: Key.confirmBeforeLock) as? Bool ?? false
        meetingExemptionEnabled = defaults.object(forKey: Key.meetingExemptionEnabled) as? Bool ?? false
        meetingMaxDeferralMinutes = Self.clamp(
            defaults.object(forKey: Key.meetingMaxDeferralMinutes) as? Int ?? Defaults.meetingMaxDeferralMinutes,
            Defaults.meetingMaxDeferralRange
        )
        rearmAfterManualUnlock = defaults.object(forKey: Key.rearmAfterManualUnlock) as? Bool ?? false
        rearmIdleMinutes = Self.clamp(
            defaults.object(forKey: Key.rearmIdleMinutes) as? Int ?? Defaults.rearmIdleMinutes,
            Defaults.rearmIdleRange
        )
        hasCompletedOnboarding = defaults.object(forKey: Key.hasCompletedOnboarding) as? Bool ?? false
        // 两个开关默认开启，但在用户主动保存信任场所 / 选择辅助设备之前不会产生任何效果。
        trustedPlaceEnabled = defaults.object(forKey: Key.trustedPlaceEnabled) as? Bool ?? true
        trustedPlaces = Self.decode(defaults.data(forKey: Key.trustedPlaces))
        fusionEnabled = defaults.object(forKey: Key.fusionEnabled) as? Bool ?? true
        auxiliaryDevices = Self.decode(defaults.data(forKey: Key.auxiliaryDevices))
        autoLockCount = defaults.object(forKey: Key.autoLockCount) as? Int ?? 0
        falseLockCount = defaults.object(forKey: Key.falseLockCount) as? Int ?? 0
    }

    @Published var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Key.isEnabled) } }
    @Published var boundWatchID: String? { didSet { defaults.set(boundWatchID, forKey: Key.boundWatchID) } }
    @Published var boundWatchName: String? { didSet { defaults.set(boundWatchName, forKey: Key.boundWatchName) } }
    /// 绑定时记录的广播类型指纹（`AppleAdvertisement.Payload.fingerprint`），用于地址轮换后校验仍是同一类广播。
    @Published var boundWatchAdvertisement: String? { didSet { defaults.set(boundWatchAdvertisement, forKey: Key.boundWatchAdvertisement) } }

    @Published var nearRSSI: Int { didSet { defaults.set(nearRSSI, forKey: Key.nearRSSI) } }
    @Published var farRSSI: Int { didSet { defaults.set(farRSSI, forKey: Key.farRSSI) } }
    @Published var smoothing: Double { didSet { defaults.set(smoothing, forKey: Key.smoothing) } }
    @Published var farDwell: Double { didSet { defaults.set(farDwell, forKey: Key.farDwell) } }
    @Published var nearDwell: Double { didSet { defaults.set(nearDwell, forKey: Key.nearDwell) } }
    @Published var signalLostTimeout: Double { didSet { defaults.set(signalLostTimeout, forKey: Key.signalLostTimeout) } }
    /// 收不到广播时是否按「已离开」锁定；关闭后只有在信号足够弱时才锁定。
    @Published var lockOnSignalLoss: Bool { didSet { defaults.set(lockOnSignalLoss, forKey: Key.lockOnSignalLoss) } }
    @Published var measuredPower: Int { didSet { defaults.set(measuredPower, forKey: Key.measuredPower) } }
    @Published var pathLossExponent: Double { didSet { defaults.set(pathLossExponent, forKey: Key.pathLossExponent) } }

    @Published var lockMethod: LockMethod { didSet { defaults.set(lockMethod.rawValue, forKey: Key.lockMethod) } }
    @Published var customLockCommand: String { didSet { defaults.set(customLockCommand, forKey: Key.customLockCommand) } }

    @Published var unlockStrategy: UnlockStrategy { didSet { defaults.set(unlockStrategy.rawValue, forKey: Key.unlockStrategy) } }
    @Published var wakeDisplayOnApproach: Bool { didSet { defaults.set(wakeDisplayOnApproach, forKey: Key.wakeDisplayOnApproach) } }
    @Published var unlockGraceAfterWake: Double { didSet { defaults.set(unlockGraceAfterWake, forKey: Key.unlockGraceAfterWake) } }

    @Published var pauseUntil: Date? {
        didSet { defaults.set(pauseUntil?.timeIntervalSince1970 ?? 0, forKey: Key.pauseUntil) }
    }

    @Published var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) } }
    @Published var showRSSIInMenuBar: Bool { didSet { defaults.set(showRSSIInMenuBar, forKey: Key.showRSSIInMenuBar) } }
    @Published var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) } }
    @Published var debugLogging: Bool { didSet { defaults.set(debugLogging, forKey: Key.debugLogging) } }
    /// 菜单栏「立即锁定」点击后是否先弹确认（默认关闭，保持一键锁屏的效率）。
    @Published var confirmBeforeLock: Bool { didSet { defaults.set(confirmBeforeLock, forKey: Key.confirmBeforeLock) } }

    /// 会议 / 演示豁免（默认关闭）：有应用阻止显示器睡眠时暂缓自动锁定。有「该锁没锁」的风险，所以默认关。
    @Published var meetingExemptionEnabled: Bool {
        didSet { defaults.set(meetingExemptionEnabled, forKey: Key.meetingExemptionEnabled) }
    }
    @Published var meetingMaxDeferralMinutes: Int {
        didSet { defaults.set(meetingMaxDeferralMinutes, forKey: Key.meetingMaxDeferralMinutes) }
    }
    /// 手动输密码解锁后，手表仍在远处时是否在键鼠空闲后重新锁定（默认关闭）。
    @Published var rearmAfterManualUnlock: Bool {
        didSet { defaults.set(rearmAfterManualUnlock, forKey: Key.rearmAfterManualUnlock) }
    }
    @Published var rearmIdleMinutes: Int {
        didSet { defaults.set(rearmIdleMinutes, forKey: Key.rearmIdleMinutes) }
    }

    /// 生成锁定闸门配置。
    var lockGateConfig: LockGate.Config {
        .init(
            meetingExemptionEnabled: meetingExemptionEnabled,
            maxDeferral: TimeInterval(Self.clamp(meetingMaxDeferralMinutes, Defaults.meetingMaxDeferralRange) * 60),
            rearmEnabled: rearmAfterManualUnlock,
            rearmIdle: TimeInterval(Self.clamp(rearmIdleMinutes, Defaults.rearmIdleRange) * 60)
        )
    }
    /// FR-01：首次启动引导是否已完成。
    @Published var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) } }

    // MARK: - 信任场所 / 辅助设备

    private static func decode<T: Decodable>(_ data: Data?) -> [T] {
        guard let data, let value = try? JSONDecoder().decode([T].self, from: data) else { return [] }
        return value
    }

    /// 在用户保存的信任场所内暂停自动锁定。没有保存任何场所时不产生效果。
    @Published var trustedPlaceEnabled: Bool {
        didSet { defaults.set(trustedPlaceEnabled, forKey: Key.trustedPlaceEnabled) }
    }
    @Published var trustedPlaces: [TrustedPlace.Place] {
        didSet { defaults.set(try? JSONEncoder().encode(trustedPlaces), forKey: Key.trustedPlaces) }
    }

    /// 让辅助设备（iPhone / AirPods）在「手表信号丢失」时暂缓锁定。没有选择任何设备时不产生效果。
    @Published var fusionEnabled: Bool {
        didSet { defaults.set(fusionEnabled, forKey: Key.fusionEnabled) }
    }
    @Published var auxiliaryDevices: [AuxiliaryDevice] {
        didSet { defaults.set(try? JSONEncoder().encode(auxiliaryDevices), forKey: Key.auxiliaryDevices) }
    }

    var fusionConfig: PresenceFusion.Config {
        .init(enabled: fusionEnabled && !auxiliaryDevices.isEmpty)
    }

    /// 自动锁定次数（自动调统样本分母）。
    @Published var autoLockCount: Int { didSet { defaults.set(autoLockCount, forKey: Key.autoLockCount) } }
    /// 用户标记为「误锁」的次数。
    @Published var falseLockCount: Int { didSet { defaults.set(falseLockCount, forKey: Key.falseLockCount) } }

    /// 当前所处的信任场所名称。**运行时状态，不落盘**，由 `AppSession` 根据网络环境维护。
    ///
    /// 放在这里是为了让 `isPaused` 成为「是否暂停」的唯一出口：`UnlockService`、菜单栏、
    /// 扫描占空策略等所有已有的 `isPaused` 判断无需逐个修改就自动尊重信任场所。
    @Published var activeTrustedPlaceName: String?
    /// 用户在菜单栏点了「恢复」：在离开当前场所之前不再按信任场所暂停。
    @Published var trustedPlaceOverridden = false

    /// 是否正因「处于信任场所」而暂停（与手动暂停独立，两者任一成立即视为暂停）。
    var isTrustedPlacePausing: Bool {
        trustedPlaceEnabled && activeTrustedPlaceName != nil && !trustedPlaceOverridden
    }

    /// 仅手动暂停（菜单栏「暂停 N 分钟」）是否仍在有效期内。
    func isManuallyPaused(now: Date) -> Bool {
        guard let pauseUntil else { return false }
        return pauseUntil > now
    }

    var isPaused: Bool { isPaused(now: Date()) }

    /// 传入显式时间便于单元测试（FR-06 暂停到期自动恢复）。
    func isPaused(now: Date) -> Bool {
        isManuallyPaused(now: now) || isTrustedPlacePausing
    }

    func pause(minutes: Double) {
        pauseUntil = Date().addingTimeInterval(minutes * 60)
    }

    func resume() {
        pauseUntil = nil
    }

    // MARK: - 自动调参样本

    /// 当前阈值（自动调参的输入）。
    var currentFarThresholds: AutoTuner.Thresholds {
        .init(farRSSI: farRSSI, farDwell: farDwell)
    }

    /// 默认阈值（自动调参的回归目标）。
    static let defaultFarThresholds = AutoTuner.Thresholds(farRSSI: -70, farDwell: 5)

    var tuningFeedback: AutoTuner.Feedback {
        .init(autoLocks: autoLockCount, falseLocks: falseLockCount)
    }

    func recordAutoLock() {
        autoLockCount += 1
    }

    /// 记录一次误锁反馈，并返回按新样本给出的调参建议。
    @discardableResult
    func recordFalseLock() -> AutoTuner.Thresholds? {
        falseLockCount += 1
        return AutoTuner.suggest(
            current: currentFarThresholds,
            feedback: tuningFeedback,
            defaults: Self.defaultFarThresholds,
            nearRSSI: nearRSSI
        )
    }

    /// 写入绑定/基准位置自动校准的结果。
    func applyAutoCalibration(_ result: DistanceCalibrator.AutoResult) {
        measuredPower = result.measuredPower
        nearRSSI = result.nearRSSI
        farRSSI = result.farRSSI
    }

    func applyTuned(_ thresholds: AutoTuner.Thresholds) {
        farRSSI = thresholds.farRSSI
        farDwell = thresholds.farDwell
    }

    func resetTuningStats() {
        autoLockCount = 0
        falseLockCount = 0
    }

    /// 生成引擎配置。
    var proximityConfig: ProximityEngine.Config {
        .init(
            nearRSSI: nearRSSI,
            farRSSI: farRSSI,
            smoothing: smoothing,
            farDwell: farDwell,
            nearDwell: nearDwell,
            signalLostTimeout: signalLostTimeout,
            lockOnSignalLoss: lockOnSignalLoss,
            measuredPower: measuredPower,
            pathLossExponent: pathLossExponent
        )
    }
}
