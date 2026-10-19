import SwiftUI

/// 校准采样目标（FR-14）。
enum CalibrationTarget: String, CaseIterable, Identifiable {
    case atDesk
    case oneMeter
    case near
    case far

    var id: String { rawValue }

    var title: String {
        switch self {
        case .atDesk: return String(localized: "以当前位置为「在身边」基准")
        case .oneMeter: return String(localized: "标定 1 米处")
        case .near: return String(localized: "在此处算作「在身边」")
        case .far: return String(localized: "在此处算作「已离开」")
        }
    }

    var guidance: String {
        switch self {
        case .atDesk: return String(localized: "按日常办公姿势坐好，点击后保持手表不动；结束后会自动生成在身边 / 已离开阈值。")
        case .oneMeter: return String(localized: "把手表放在离 Mac 约 1 米的位置，点击后保持不动。")
        case .near: return String(localized: "坐回正常办公位置，点击后保持不动。")
        case .far: return String(localized: "走到你希望自动锁屏的位置，点击后保持不动。")
        }
    }

    /// 采样时长（秒）。
    var duration: Int { 10 }
}

/// 校准流程控制器：按秒采集当前平滑 RSSI，采样结束后写入设置。
@MainActor
final class CalibrationController: ObservableObject {
    /// 结果文案的语义，决定界面上的颜色。
    enum MessageKind {
        case info
        case success
        case warning
    }

    @Published private(set) var isSampling = false
    @Published private(set) var remaining = 0
    @Published private(set) var target: CalibrationTarget = .oneMeter
    @Published private(set) var message: String?
    @Published private(set) var messageKind: MessageKind = .info
    @Published private(set) var sampleCount = 0
    @Published private(set) var lastSampleRSSI: Int?

    var progress: Double {
        guard isSampling, target.duration > 0 else { return 0 }
        return Double(target.duration - remaining) / Double(target.duration)
    }

    private let session: AppSession
    private let settings: SettingsStore
    private var samples: [Int] = []
    private var nearSamples: [Int] = []
    private var farSamples: [Int] = []
    private var timer: Timer?

    init(session: AppSession, settings: SettingsStore) {
        self.session = session
        self.settings = settings
    }

    func start(_ target: CalibrationTarget) {
        guard !isSampling else { return }
        self.target = target
        samples = []
        sampleCount = 0
        lastSampleRSSI = nil
        remaining = target.duration
        isSampling = true
        message = String(localized: "正在采样「\(target.title)」，请保持不动…")
        messageKind = .info
        DiagnosticsLog.shared.append(.info, String(localized: "开始校准采样：\(target.title)"))
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func cancel() {
        guard isSampling else { return }
        timer?.invalidate()
        timer = nil
        isSampling = false
        samples = []
        message = String(localized: "已取消采样")
        messageKind = .info
    }

    func reset() {
        cancel()
        nearSamples = []
        farSamples = []
        message = nil
        messageKind = .info
    }

    private func tick() {
        guard isSampling else { return }
        let value = session.smoothedRSSI
        if value < 0 { samples.append(Int(value.rounded())) }
        sampleCount = samples.count
        lastSampleRSSI = samples.last
        remaining -= 1
        guard remaining <= 0 else { return }
        timer?.invalidate()
        timer = nil
        isSampling = false
        finish()
    }

    private func finish() {
        guard !samples.isEmpty else {
            message = String(localized: "未采集到手表信号，请确认已绑定手表并在蓝牙范围内")
            messageKind = .warning
            DiagnosticsLog.shared.append(.warning, String(localized: "校准失败：\(target.title) 没有可用样本"))
            return
        }

        switch target {
        case .atDesk:
            let result = DistanceCalibrator.autoThresholds(
                from: samples,
                fallback: .init(
                    nearRSSI: settings.nearRSSI,
                    farRSSI: settings.farRSSI,
                    measuredPower: settings.measuredPower
                )
            )
            settings.applyAutoCalibration(result)
            message = String(localized: "已按当前位置设置：1 米标定 \(result.measuredPower)、在身边 \(result.nearRSSI)、已离开 \(result.farRSSI) dBm（\(samples.count) 个样本）")
            messageKind = .success
        case .oneMeter:
            let value = DistanceCalibrator.measuredPower(samples: samples, fallback: settings.measuredPower)
            settings.measuredPower = value
            message = String(localized: "已写入 1 米标定值 \(value) dBm（\(samples.count) 个样本）")
            messageKind = .success
        case .near:
            nearSamples = samples
            message = String(localized: "已记录「在身边」样本 \(samples.count) 个，请再采样「已离开」位置")
            messageKind = .success
        case .far:
            farSamples = samples
            guard !nearSamples.isEmpty else {
                message = String(localized: "请先采样「在身边」位置，再采样当前位置")
                messageKind = .warning
                return
            }
            let result = DistanceCalibrator.thresholds(
                nearSamples: nearSamples,
                farSamples: farSamples,
                fallback: .init(nearRSSI: settings.nearRSSI, farRSSI: settings.farRSSI)
            )
            settings.nearRSSI = result.nearRSSI
            settings.farRSSI = result.farRSSI
            message = String(localized: "已生成阈值：在身边 \(result.nearRSSI) dBm / 已离开 \(result.farRSSI) dBm")
            messageKind = .success
        }
        DiagnosticsLog.shared.append(.info, String(localized: "校准完成：\(message ?? "")"))
    }
}

/// 校准向导界面（「设置 → 校准」）。
///
/// 采样目标由横排按钮改为竖排单选卡（长标题不再挤压），采样过程给出进度与实时信号。
struct CalibrationWizardView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @StateObject private var controller = CalibrationController(
        session: AppSession.shared,
        settings: SettingsStore.shared
    )

    @State private var target: CalibrationTarget = .atDesk

    var body: some View {
        FormCard(
            title: String(localized: "距离校准向导"),
            subtitle: String(localized: "把手表放到指定位置后点「开始采样」，应用会采集 \(target.duration) 秒信号并自动写入参数。")
        ) {
            VStack(alignment: .leading, spacing: WLSpacing.xs) {
                ForEach(CalibrationTarget.allCases) { item in
                    RadioCard(title: item.title, subtitle: item.guidance, isSelected: target == item) {
                        target = item
                    }
                    .disabled(controller.isSampling)
                }
            }

            HStack(spacing: WLSpacing.sm) {
                if controller.isSampling {
                    WLButton(String(localized: "取消采样"), role: .danger, width: 110) { controller.cancel() }
                } else {
                    WLButton(String(localized: "开始采样"), systemImage: "record.circle", role: .primary, width: 110) {
                        controller.start(target)
                    }
                }
                Spacer(minLength: 0)
            }

            if controller.isSampling { samplingProgress }

            if let message = controller.message {
                Label(message, systemImage: messageSymbol)
                    .font(.caption)
                    .foregroundStyle(messageColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack(spacing: WLSpacing.sm) {
                Text("当前：1 米标定 \(settings.measuredPower) · 在身边 \(settings.nearRSSI) · 已离开 \(settings.farRSSI)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer(minLength: WLSpacing.sm)
                WLButton(String(localized: "重置已采集样本"), isDisabled: controller.isSampling, width: 130) {
                    controller.reset()
                }
            }
        }
    }

    private var samplingProgress: some View {
        VStack(alignment: .leading, spacing: WLSpacing.xs) {
            ProgressView(value: controller.progress)
            HStack(spacing: WLSpacing.sm) {
                Text("剩余 \(controller.remaining) 秒")
                if controller.sampleCount > 0 {
                    Text("已采 \(controller.sampleCount) 个样本")
                }
                if let rssi = controller.lastSampleRSSI {
                    Text("当前 \(rssi) dBm")
                }
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
    }

    private var messageSymbol: String {
        switch controller.messageKind {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle"
        }
    }

    private var messageColor: Color {
        switch controller.messageKind {
        case .success: return WLColor.success
        case .warning: return WLColor.warning
        case .info: return Color.secondary
        }
    }
}
