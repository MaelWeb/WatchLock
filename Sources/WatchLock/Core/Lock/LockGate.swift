import Foundation

/// 自动锁定的「闸门」：在状态机已决定锁屏之后，决定是现在锁、暂缓，还是之后补锁。
///
/// 两个互相独立、默认都关闭的选项：
/// - **会议 / 演示豁免**：有应用持有「阻止显示器睡眠」断言时暂缓锁定，结束后补锁；
///   暂缓有硬上限，到点无论如何都锁（防止浏览器视频等让锁屏长期失效）。
/// - **手动解锁后重新布防**：用户手动解锁时若手表仍判定为「已离开」，则键鼠空闲满设定时间后再锁一次。
///   用空闲判据而不是固定延时，是为了不在你正在操作时突然锁屏。
///
/// 手表回到身边、暂停 / 关闭、整机睡眠或屏幕已锁定时，任何待处理动作都应由调用方 `cancel()`。
final class LockGate {
    struct Config: Equatable {
        var meetingExemptionEnabled = false
        var maxDeferral: TimeInterval = 60 * 60
        var rearmEnabled = false
        var rearmIdle: TimeInterval = 5 * 60
    }

    /// 允许执行的锁定。
    struct Grant: Equatable {
        let reason: String
        /// 重新布防产生的锁定与距离阈值无关，不应计入「误锁反馈 / 自动调参」样本。
        let isRearm: Bool
    }

    private let config: () -> Config
    private let holders: () -> [DisplaySleepHolder]
    private let idleSeconds: () -> TimeInterval?
    private let now: () -> Date

    private(set) var deferredSince: Date?
    private var deferredReason: String?
    private var deferredIsRearm = false
    private(set) var isRearmArmed = false
    /// 最近一次探测到的持有者（仅供界面提示）。
    private(set) var currentHolders: [DisplaySleepHolder] = []

    init(
        config: @escaping () -> Config,
        holders: @escaping () -> [DisplaySleepHolder] = { MeetingExemption.currentHolders() },
        idleSeconds: @escaping () -> TimeInterval? = { PowerAssertionProbe.idleSeconds() },
        now: @escaping () -> Date = { Date() }
    ) {
        self.config = config
        self.holders = holders
        self.idleSeconds = idleSeconds
        self.now = now
    }

    var isDeferring: Bool { deferredSince != nil }

    /// 菜单栏提示文案；没有暂缓时为 `nil`。
    var deferralNote: String? {
        guard isDeferring else { return nil }
        let names = Array(Set(currentHolders.map(\.processName))).sorted()
        return names.isEmpty
            ? "会议 / 演示进行中，已暂缓锁定"
            : "会议 / 演示进行中（\(names.prefix(2).joined(separator: "、"))），已暂缓锁定"
    }

    /// 状态机要求锁屏时调用。返回要立即执行的锁定；返回 `nil` 表示已暂缓。
    func request(reason: String) -> Grant? {
        evaluate(reason: reason, isRearm: false)
    }

    private func evaluate(reason: String, isRearm: Bool) -> Grant? {
        let current = config()
        let list = current.meetingExemptionEnabled ? holders() : []
        let decision = MeetingExemption.decide(
            enabled: current.meetingExemptionEnabled,
            holders: list,
            deferredSince: deferredSince,
            now: now(),
            maxDeferral: current.maxDeferral
        )
        switch decision {
        case .lockNow:
            let wasDeferred = isDeferring
            clearDeferral()
            isRearmArmed = false
            return Grant(reason: wasDeferred ? "\(reason)（会议 / 演示结束后）" : reason, isRearm: isRearm)
        case .lockCapped:
            clearDeferral()
            isRearmArmed = false
            return Grant(reason: "\(reason)（已暂缓满上限）", isRearm: isRearm)
        case .deferLock:
            currentHolders = list
            if deferredSince == nil {
                deferredSince = now()
                deferredReason = reason
                deferredIsRearm = isRearm
                DiagnosticsLog.shared.append(
                    .info,
                    "检测到会议 / 演示（\(list.map(\.processName).joined(separator: "、"))），暂缓锁定：\(reason)"
                )
            }
            return nil
        }
    }

    /// 会话被解锁时调用。仅当选项开启且手表仍判定为「已离开」时布防。
    func screenUnlocked(watchIsFar: Bool) {
        guard config().rearmEnabled, watchIsFar, !isRearmArmed else { return }
        isRearmArmed = true
        DiagnosticsLog.shared.append(.info, "手动解锁时手表仍在远处，已布防：键鼠空闲后将再次锁定")
    }

    /// 由 1 秒 housekeeping 驱动。返回要立即执行的锁定，`nil` 表示无事可做。
    func tick(watchIsFar: Bool) -> Grant? {
        if isDeferring {
            guard watchIsFar else {
                cancel()
                return nil
            }
            return evaluate(reason: deferredReason ?? "手表离开设定范围", isRearm: deferredIsRearm)
        }

        guard isRearmArmed else { return nil }
        guard watchIsFar, config().rearmEnabled else {
            isRearmArmed = false
            return nil
        }
        guard let idle = idleSeconds(), idle >= config().rearmIdle else { return nil }
        isRearmArmed = false
        return evaluate(reason: "手动解锁后手表仍在远处，且键鼠已空闲", isRearm: true)
    }

    /// 手表回到身边、暂停 / 关闭、整机睡眠、会话已锁定等：放弃所有待处理动作。
    func cancel() {
        if isDeferring { DiagnosticsLog.shared.append(.info, "取消暂缓的锁定") }
        clearDeferral()
        isRearmArmed = false
    }

    private func clearDeferral() {
        deferredSince = nil
        deferredReason = nil
        deferredIsRearm = false
        currentHolders = []
    }
}
