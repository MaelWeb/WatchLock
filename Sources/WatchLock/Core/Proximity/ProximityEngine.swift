import Foundation

/// 依据 RSSI 样本判断手表「在身边 / 已离开」的状态机。
///
/// 设计要点：
/// 1. 使用 EWMA 平滑 RSSI，抑制 BLE 抖动；
/// 2. 使用「近/远双阈值 + 持续时间」实现迟滞，避免在临界点反复锁定；
/// 3. 支持信号丢失超时，防止手表关机/出电梯后长时间不触发。
final class ProximityEngine {
    /// 触发「已离开」的原因，用于日志与通知中区分「超出范围」与「信号丢失」。
    enum FarReason: String {
        case beyondThreshold
        case signalLost

        var title: String {
            switch self {
            case .beyondThreshold: return String(localized: "手表离开设定范围")
            case .signalLost: return String(localized: "超过设定时间未收到手表信号")
            }
        }
    }

    enum Event {
        case becameNear
        case becameFar(reason: FarReason)
    }

    struct Config {
        /// 判定为「在身边」的 RSSI 上限（含），例如 -55。
        var nearRSSI: Int = -55
        /// 判定为「已离开」的 RSSI 下限（含），例如 -70。
        var farRSSI: Int = -70
        /// EWMA 平滑系数，越小越平滑。
        var smoothing: Double = 0.25
        /// 状态切换需要持续的秒数。
        var farDwell: TimeInterval = 5
        var nearDwell: TimeInterval = 1
        /// 超过该时间没有新样本则视为信号丢失。
        var signalLostTimeout: TimeInterval = 20
        /// 信号丢失时是否判定为「已离开」。关闭后只有真正超出距离才会锁定。
        var lockOnSignalLoss: Bool = true
        /// 丢失前最后一次信号仍很强（≥ 在身边阈值）时，超时时间的放大倍数。
        ///
        /// 依据：Apple 设备的 BLE 广播会随设备状态（屏幕开关、连接状态）动态启停，
        /// 且以随机地址 + IRK 的形式发出（见 Apple 开发者论坛「IRK-resolvable advertisements
        /// stops after screen turns off」，以及 `docs/anti-false-lock-research.md`）。
        /// 因此「十几秒没收到广播」并不等于人走开了，此时按信号丢失锁屏属于误锁。
        var nearSignalLossFactor: Double = 2.5
        /// 1 米处的标定 RSSI，用于距离估算。
        var measuredPower: Int = -55
        /// 路径损耗指数。
        var pathLossExponent: Double = 2.5
    }

    var config: Config
    var onEvent: ((Event) -> Void)?
    var onSample: ((ProximitySample) -> Void)?

    private(set) var status: ProximityStatus = .unknown
    private(set) var lastSample: ProximitySample?

    private var smoothedRSSI: Double?
    private var lastSampleDate: Date?
    private var pending: ProximityStatus?
    private var pendingSince: Date?
    private var timer: Timer?
    private var signalLostReported = false

    init(config: Config = .init()) {
        self.config = config
    }

    func start() {
        stop()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        smoothedRSSI = nil
        lastSampleDate = nil
        pending = nil
        pendingSince = nil
        status = .unknown
        lastSample = nil
        signalLostReported = false
    }

    /// 收到广播但系统没给有效信号强度（RSSI=127）时调用：设备仍在附近，只是测不到强度。
    ///
    /// 只刷新「最后一次见到」的时间，不动平滑信号与状态。否则 macOS 蓝牙栈在一段时间内
    /// 对所有广播都返回 127 时，状态机会因为收不到样本而判定「信号丢失」并锁屏——
    /// 实测这正是「手表在旁边却锁屏」的一条真实路径。
    func notePresence(at date: Date = Date()) {
        guard let last = lastSampleDate, date > last else { return }
        lastSampleDate = date
        signalLostReported = false
    }

    func update(rssi: Int, at date: Date = Date()) {
        let value = Double(rssi)
        if let current = smoothedRSSI {
            smoothedRSSI = current + config.smoothing * (value - current)
        } else {
            smoothedRSSI = value
        }
        lastSampleDate = date
        signalLostReported = false

        let smoothed = smoothedRSSI ?? value
        let distance = estimateDistance(rssi: smoothed)
        let sample = ProximitySample(smoothedRSSI: smoothed, estimatedDistance: distance, date: date)
        lastSample = sample
        onSample?(sample)

        evaluate(smoothed: smoothed, now: date)
    }

    /// 当前生效的信号丢失超时（最后一次信号很强时会放宽，见 `nearSignalLossFactor`）。
    var effectiveSignalLostTimeout: TimeInterval {
        guard let smoothed = lastSample?.smoothedRSSI, smoothed >= Double(config.nearRSSI) else {
            return config.signalLostTimeout
        }
        return config.signalLostTimeout * config.nearSignalLossFactor
    }

    /// 结算入口：由 1 秒定时器驱动，也可由测试以指定时间直接调用。
    func tick(now: Date = Date()) {
        guard let last = lastSampleDate else { return }
        let timeout = effectiveSignalLostTimeout
        if now.timeIntervalSince(last) >= timeout {
            if !signalLostReported {
                signalLostReported = true
                DiagnosticsLog.shared.append(.warning, String(localized: "超过 \(Int(timeout)) 秒未收到手表信号"))
            }
            guard config.lockOnSignalLoss else { return }
            commit(.far, reason: .signalLost)
            lastSampleDate = now
            return
        }
        if let smoothed = smoothedRSSI {
            evaluate(smoothed: smoothed, now: now)
        }
    }

    private func evaluate(smoothed: Double, now: Date) {
        let target: ProximityStatus?
        if smoothed >= Double(config.nearRSSI) {
            target = .near
        } else if smoothed <= Double(config.farRSSI) {
            target = .far
        } else {
            target = nil
        }

        guard let target else {
            pending = nil
            pendingSince = nil
            return
        }

        if pending != target {
            pending = target
            pendingSince = now
            return
        }

        let dwell = target == .far ? config.farDwell : config.nearDwell
        if let pendingSince, now.timeIntervalSince(pendingSince) >= dwell {
            commit(target)
        }
    }

    private func commit(_ newStatus: ProximityStatus, reason: FarReason = .beyondThreshold) {
        guard newStatus != status else { return }
        status = newStatus
        pending = nil
        pendingSince = nil
        switch newStatus {
        case .near:
            DiagnosticsLog.shared.append(.info, String(localized: "手表进入近距离"))
            onEvent?(.becameNear)
        case .far:
            DiagnosticsLog.shared.append(.info, reason.title)
            onEvent?(.becameFar(reason: reason))
        default:
            break
        }
    }

    /// 依据对数路径损耗模型估算距离（米）。
    func estimateDistance(rssi: Double) -> Double {
        let ratio = (Double(config.measuredPower) - rssi) / (10 * config.pathLossExponent)
        return pow(10, ratio)
    }
}
