import AppKit
import SwiftUI

/// FR-01 首次启动引导（v2）。
///
/// 依据 Apple HIG《Onboarding》与《Privacy → Requesting permission》重设计：
/// 1. 权限步是「预说明屏」：**只给一个主按钮**，不提供跳过 / 关闭等绕开系统授权的路径，
///    按钮文案不叫「允许」；用户跳去系统设置授权成功后**自动**进入下一步。
/// 2. 绑定步用真实交互教学（选手表本身就是操作）。
/// 3. 完成步遵循「推迟非必要自定义」：不罗列参数（那是设置页的职责），
///    只保留用户真正要去系统里做的一件事 —— 打开「使用 Apple Watch 解锁」。
struct OnboardingView: View {
    @EnvironmentObject private var session: AppSession
    @ObservedObject private var settings = SettingsStore.shared

    @State private var step: Step = .permission
    @State private var showAllDevices = false
    /// 用户已点过「打开系统设置」：之后蓝牙变为可用时自动进入下一步。
    @State private var awaitingPermission = false

    let onFinish: () -> Void

    private enum Step: Int, CaseIterable {
        case permission
        case device
        case ready

        var title: String {
            switch self {
            case .permission: return String(localized: "授权")
            case .device: return String(localized: "绑定")
            case .ready: return String(localized: "就绪")
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            artBand
            ScrollView {
                stepContent
                    .frame(maxWidth: Layout.contentWidth)
                    .padding(.vertical, WLSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            Divider()
            footer
                .padding(.vertical, WLSpacing.md)
                .padding(.horizontal, WLSpacing.lg)
        }
        .frame(minWidth: 560, minHeight: 470)
        .onChange(of: session.bluetoothState) { _, newState in
            // 授权是在系统设置里完成的，回来时蓝牙就绪 —— 不让用户再点一次「下一步」。
            guard awaitingPermission, newState == .poweredOn else { return }
            awaitingPermission = false
            advance()
        }
    }

    private enum Layout {
        /// 正文限宽：窗口放大时内容不被拉得过长，标题与说明保持居中阅读。
        static let contentWidth: CGFloat = 460
        static let artHeight: CGFloat = 84
    }

    // MARK: - 插画顶带

    /// 顶带：一幅「Mac — 信号 — 手表」线稿 + 步骤圆点。
    ///
    /// 插画随步骤变化（待授权 / 搜索中 / 就绪），替代原来每一步都重复的「欢迎」条与独立步骤条：
    /// 上半屏不再空着，窗口也多出一截给内容。背景忽略顶部安全区，品牌色延伸到窗口最上沿，
    /// 红绿灯悬浮其上。依据与备选方案见 `docs/ui-design/.scratch/INDEX.md`。
    private var artBand: some View {
        VStack(spacing: WLSpacing.sm) {
            OnboardingArt(stage: artStage)
                .frame(height: Layout.artHeight)
            StepIndicator(titles: Step.allCases.map(\.title), current: step.rawValue)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("第 \(step.rawValue + 1) 步，共 \(Step.allCases.count) 步：\(step.title)")
        }
        .padding(.top, WLSpacing.sm) // 安全区已避开红绿灯，这里只做节奏
        .padding(.bottom, WLSpacing.md)
        .frame(maxWidth: .infinity)
        .background(
            WLColor.accent.opacity(0.07)
                .ignoresSafeArea(.container, edges: .top)
        )
    }

    private var artStage: OnboardingArtStage {
        OnboardingArtStage.stage(forStep: step.rawValue, bluetoothReady: session.bluetoothState == .poweredOn)
    }

    /// 步骤标题 + 说明，统一居中。
    private func header(_ title: String, lead: String? = nil, eyebrow: String? = nil) -> some View {
        VStack(spacing: WLSpacing.xs) {
            if let eyebrow {
                Text(eyebrow)
                    .font(WLFont.caption)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            if let lead {
                Text(lead)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 步骤 1：蓝牙权限（预说明屏）

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .permission: permissionStep
        case .device: deviceStep
        case .ready: readyStep
        }
    }

    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: WLSpacing.md) {
            header(
                String(localized: "先授权蓝牙"),
                lead: String(localized: "WatchLock 靠手表的蓝牙信号判断你在不在电脑旁，没有蓝牙它无法工作。"),
                eyebrow: String(localized: "欢迎使用 \(BrandLogo.name)")
            )
            statusCard

            DisclosureGroup("为什么需要蓝牙权限？") {
                VStack(alignment: .leading, spacing: WLSpacing.xs) {
                    permissionBullet(String(localized: "扫描 Apple Watch 的 BLE 广播，估算它与 Mac 的距离"))
                    permissionBullet(String(localized: "全部在本机计算，仅在你点「检查更新」时联网，不上传任何数据"))
                    permissionBullet(String(localized: "只申请蓝牙访问，不涉及密码、文件或屏幕内容"))
                }
                .font(.callout)
                .padding(.vertical, WLSpacing.xs)
            }
            .font(.callout)
        }
    }

    private func permissionBullet(_ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "checkmark")
                .foregroundStyle(WLColor.success)
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        let isReady = session.bluetoothState == .poweredOn
        HStack(spacing: WLSpacing.sm) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isReady ? WLColor.success : WLColor.warning)
                .accessibilityHidden(true)
            Text(isReady ? String(localized: "蓝牙已就绪，扫描已开始") : bluetoothStatusText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wlCard(tint: isReady ? .plain : .warning)
    }

    private var bluetoothStatusText: String {
        switch session.bluetoothState {
        case .poweredOn: return String(localized: "蓝牙已就绪，扫描已开始")
        case .poweredOff: return String(localized: "蓝牙已关闭，请在系统设置中开启")
        case .unauthorized: return String(localized: "尚未授予蓝牙权限，点击下方按钮前往系统设置")
        case .unsupported: return String(localized: "当前设备不支持低功耗蓝牙")
        case .resetting: return String(localized: "蓝牙模块正在重置，请稍候")
        case .unknown: return String(localized: "正在读取蓝牙状态…")
        @unknown default: return String(localized: "蓝牙状态未知")
        }
    }

    /// 步骤 1 的唯一主按钮：未授权 → 打开系统设置；已授权 → 继续。
    private var permissionPrimary: some View {
        let isReady = session.bluetoothState == .poweredOn
        return WLButton(
            isReady ? String(localized: "继续") : String(localized: "打开「系统设置 → 隐私与安全性 → 蓝牙」"),
            systemImage: isReady ? nil : "arrow.up.forward.app",
            role: .primary,
            width: 300
        ) {
            if isReady {
                advance()
            } else {
                awaitingPermission = true
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")!)
            }
        }
    }

    // MARK: - 步骤 2：绑定手表（交互即教学）

    private var deviceStep: some View {
        VStack(alignment: .leading, spacing: WLSpacing.md) {
            header(
                String(localized: "选一台是你的手表"),
                lead: String(localized: "手表戴在手腕上贴近 Mac，信号最强那台通常就是它。广播不带名字是 Apple 设备的常态。")
            )

            if currentDevices.isEmpty {
                EmptyStateView(
                    title: String(localized: "暂未发现候选设备"),
                    systemImage: "wave.3.right",
                    message: emptyHint
                )
            } else {
                VStack(spacing: WLSpacing.xs) {
                    ForEach(Array(currentDevices.enumerated()), id: \.element.id) { index, device in
                        DeviceRow(
                            device: device,
                            nearRSSI: settings.nearRSSI,
                            farRSSI: settings.farRSSI,
                            isBound: settings.boundWatchID == device.id.uuidString,
                            actionTitle: settings.boundWatchID == device.id.uuidString ? String(localized: "已绑定") : String(localized: "选择"),
                            actionHelp: String(localized: "绑定后按设备标识追踪，广播地址轮换时会自动续接")
                        ) {
                            session.bind(watch: device)
                        }
                        if showAllDevices, DeveloperMode.isEnabled {
                            Text(device.advertisementSummary)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }
                        if index < currentDevices.count - 1 { Divider() }
                    }
                }
            }

            HStack(spacing: WLSpacing.sm) {
                Button(showAllDevices ? String(localized: "只显示推荐设备") : String(localized: "看不到设备？显示全部")) {
                    showAllDevices.toggle()
                }
                .buttonStyle(.borderless)
                .font(.caption)
                if showAllDevices, DeveloperMode.isEnabled {
                    Button("复制诊断信息") { copyDiagnostics() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// 直接在 body 求值中读取最新扫描结果，避免依赖定时器刷新（定时器在 body 重建时会被重置）。
    private var currentDevices: [DiscoveredWatch] {
        showAllDevices ? session.allDiscoveredDevices() : session.bindingCandidates()
    }

    private var emptyHint: String {
        guard session.bluetoothState == .poweredOn else {
            return String(localized: "蓝牙未就绪：\(session.bluetoothState.title)。请先回到上一步完成授权。")
        }
        return String(localized: "请确认手表已解锁、蓝牙开启，并保持在 Mac 附近。可点下方「显示全部」确认扫描是否正常。")
    }

    // MARK: - 步骤 3：就绪（不做非必要自定义）

    private var readyStep: some View {
        VStack(alignment: .leading, spacing: WLSpacing.md) {
            // 对勾已由顶部插画（手表角标）表达，这里只留标题与摘要，不再重复画一个大勾。
            header(
                String(localized: "一切就绪"),
                lead: String(localized: "已绑定 \(settings.boundWatchName ?? "Apple Watch") · 默认阈值：在身边 \(settings.nearRSSI) / 已离开 \(settings.farRSSI) dBm")
            )

            // HIG：引导里只保留真正必要的动作。解锁只能由系统完成，这是用户唯一还要去系统做的事。
            HStack(spacing: WLSpacing.md) {
                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .font(.system(size: 18))
                    .foregroundStyle(WLColor.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: WLSpacing.xxs) {
                    Text("开启系统「使用 Apple Watch 解锁」")
                    Text("解锁只能由系统完成，这一步需要你在系统设置里打开。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: WLSpacing.sm)
                WLButton(String(localized: "打开系统设置")) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension")!)
                }
                // 按内容取宽：WLButton 的标签默认撑满可用宽度，会把左侧说明挤成两行。
                .fixedSize(horizontal: true, vertical: false)
            }
            .wlCard()

            Text("其余参数已按默认值设置好，随时可在菜单栏 → 设置里调整。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 底部按钮

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: WLSpacing.sm) {
            if step != .permission {
                WLButton(String(localized: "上一步"), width: 90) { back() }
            }
            // HIG：权限预说明屏不允许出现「跳过」等绕开授权的路径。
            if step == .device {
                Button("跳过") { finish() }
                    .buttonStyle(.borderless)
                    .font(.callout)
            }
            Spacer(minLength: 0)
            switch step {
            case .permission:
                permissionPrimary
            case .device:
                WLButton(String(localized: "继续"), role: .primary, isDisabled: settings.boundWatchID == nil, width: 110) {
                    advance()
                }
                .help(settings.boundWatchID == nil ? String(localized: "先绑定一台手表后继续") : "")
            case .ready:
                WLButton(String(localized: "开始使用"), role: .primary, width: 110) { finish() }
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
    }

    private func advance() {
        step = Step(rawValue: step.rawValue + 1) ?? .ready
    }

    private func back() {
        step = Step(rawValue: step.rawValue - 1) ?? .permission
    }

    private func finish() {
        settings.hasCompletedOnboarding = true
        onFinish()
    }

    /// 把当前可见设备的广播摘要复制到剪贴板，便于排查「识别不到手表」。
    private func copyDiagnostics() {
        let devices = currentDevices
        let text = devices.map { "[\($0.rssi) dBm] \($0.advertisementSummary)" }
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        DiagnosticsLog.shared.append(.info, String(localized: "已复制 \(devices.count) 台设备的诊断信息"))
    }
}

/// 引导窗口的宿主控制器（LSUIElement 应用没有主窗口，直接用 NSWindow 承载）。
@MainActor
enum OnboardingWindow {
    static func present(session: AppSession) {
        let root = OnboardingView(onFinish: { OnboardingWindow.close() })
            .environmentObject(session)
        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 470),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "WatchLock 设置向导")
        // 品牌区延伸到标题栏：隐藏标题文字并让标题栏透明（红绿灯仍保留，可随时关窗）。
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        current = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    static func close() {
        current?.close()
        current = nil
    }

    private static var current: NSWindow?
}
