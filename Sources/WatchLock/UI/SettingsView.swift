import SwiftUI

/// 设置窗口的页面。
///
/// 原来是一个 5 页 `TabView`，其中「高级」塞了 6 个模块，内容远超一屏导致
/// 嵌套滚动。改为侧栏 + 独立页面，并把「高级」拆成「校准」与「诊断」
/// （见 `docs/ui-design.md` §4）。
enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case device
    case unlock
    case calibration
    case diagnostics
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .device: return "设备"
        case .unlock: return "解锁"
        case .calibration: return "校准"
        case .diagnostics: return "诊断"
        case .about: return "关于"
        }
    }

    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .device: return "applewatch"
        case .unlock: return "lock.open"
        case .calibration: return "ruler"
        case .diagnostics: return "stethoscope"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var session: AppSession
    @State private var selection: SettingsPage = .general

    var body: some View {
        // 自绘侧栏而不是 NavigationSplitView：后者会带一条工具栏（侧栏开关 + 标题），
        // 与透明标题栏叠加后在详情区顶部堆出一大条空白；自绘侧栏与设计稿一致，
        // 内容从红绿灯安全区下方开始，没有多余的顶部空带。
        HStack(spacing: 0) {
            sidebar
            // 给分隔线预留 1pt：否则详情区的不透明背景会从 x=168 起直接盖住底层的线。
            Color.clear.frame(width: 1)
            detail
        }
        .frame(minWidth: 680, minHeight: 620)
        // 分隔线画在窗口底层背景里并整体忽略安全区：从红绿灯条带一直贯通到底。
        // （画在侧栏 overlay 里时布局被限制在安全区内，顶部会断一截。）
        .background {
            HStack(spacing: 0) {
                Color.clear.frame(width: 168)
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
                Color.clear
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
    }

    // MARK: 侧栏

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: WLSpacing.xxs) {
            // 侧栏顶部品牌标识：条目之上留出一段，避免与红绿灯抢空间。
            BrandLockup(size: 24, font: .subheadline.weight(.semibold))
                .padding(.bottom, WLSpacing.sm)
            ForEach(SettingsPage.allCases) { page in
                SidebarButton(
                    page: page,
                    isSelected: selection == page,
                    action: { selection = page }
                )
            }
            Spacer(minLength: 0)
        }
        .padding(WLSpacing.sm)
        .frame(width: 168)
        .background(.regularMaterial, ignoresSafeAreaEdges: .top)
    }

    private var detail: some View {
        detail(for: selection)
            .environmentObject(session)
            // 统一详情列底色：Form（grouped）/ ScrollView 自带的内容背景与顶部安全区
            // 条带的 windowBackgroundColor 是两种灰，拼出横向接缝。隐藏自带背景后，
            // 整列改用同一个 windowBackgroundColor，从红绿灯条带一直铺到底。
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .windowBackgroundColor), ignoresSafeAreaEdges: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func detail(for page: SettingsPage) -> some View {
        switch page {
        case .general: GeneralPage()
        case .device: DevicePage()
        case .unlock: UnlockPage()
        case .calibration: CalibrationPage()
        case .diagnostics: DiagnosticsPage()
        case .about: AboutPage()
        }
    }
}

/// 设置窗口侧栏条目：图标 + 文字 + 选中态强调色底，样式对齐设计稿（`03~07` 的侧栏）。
private struct SidebarButton: View {
    let page: SettingsPage
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: WLSpacing.sm) {
                Image(systemName: page.symbolName)
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Color.white : WLColor.accent)
                Text(page.title)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, WLSpacing.sm)
            .padding(.vertical, 5)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: WLRadius.sm, style: .continuous)
                        .fill(WLColor.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("切换到「\(page.title)」页")
        .accessibilityLabel(page.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - 通用

private struct GeneralPage: View {
    @EnvironmentObject private var session: AppSession
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        Form {
            Section {
                Toggle("启用自动锁定", isOn: $settings.isEnabled)
                    .help("关闭后不再自动锁定，菜单栏只显示状态")
            }

            Section("距离阈值") {
                ThresholdBand(
                    nearRSSI: nearBinding,
                    farRSSI: farBinding,
                    currentRSSI: session.smoothedRSSI
                )
                .padding(.vertical, WLSpacing.xs)
                Stepper("在身边 \(settings.nearRSSI) dBm", value: nearBinding, in: ThresholdMath.nearRange)
                    .help("信号强于该值判定为「在身边」")
                Stepper("已离开 \(settings.farRSSI) dBm", value: farBinding, in: ThresholdMath.farRange)
                    .help("信号弱于该值并持续设定秒数后锁定")
                Stepper("离开后等待 \(Int(settings.farDwell)) 秒再锁定",
                        value: $settings.farDwell, in: 0 ... 30, step: 1)
                    .help("避免路过时信号抖动导致误锁")
                Stepper("信号丢失 \(Int(settings.signalLostTimeout)) 秒视为离开",
                        value: $settings.signalLostTimeout, in: 3 ... 60, step: 1)
                    .help("手表休眠或被系统节流时会收不到广播")
                Toggle("收不到信号时按「已离开」锁定", isOn: $settings.lockOnSignalLoss)
                    .help("关闭时长时间无信号仍保持解锁")
                Text(thresholdHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("锁定方式") {
                Picker("方式", selection: $settings.lockMethod) {
                    ForEach(LockMethod.allCases) { method in
                        Text(method.title).tag(method)
                    }
                }
                Text(settings.lockMethod.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if settings.lockMethod == .systemLockScreen {
                    systemLockStatusLabel
                }
                if settings.lockMethod == .customCommand {
                    TextField("自定义命令", text: $settings.customLockCommand)
                }
            }

            Section {
                Toggle("会议 / 演示期间暂缓锁定", isOn: $settings.meetingExemptionEnabled)
                    .help("有应用阻止显示器睡眠（视频会议、全屏演示等）时，先不锁屏，结束后补锁")
                if settings.meetingExemptionEnabled {
                    Stepper("最长暂缓 \(settings.meetingMaxDeferralMinutes) 分钟，到点必锁",
                            value: $settings.meetingMaxDeferralMinutes,
                            in: SettingsStore.Defaults.meetingMaxDeferralRange, step: 5)
                        .help("硬上限：即使会议仍在进行也会锁定，避免锁屏长期失效")
                }
                Toggle("手动解锁后手表仍在远处时重新锁定", isOn: $settings.rearmAfterManualUnlock)
                    .help("例如手表在充电时你用密码解锁；键鼠空闲后会再锁一次")
                if settings.rearmAfterManualUnlock {
                    Stepper("键鼠空闲 \(settings.rearmIdleMinutes) 分钟后重新锁定",
                            value: $settings.rearmIdleMinutes,
                            in: SettingsStore.Defaults.rearmIdleRange)
                        .help("按键鼠空闲计时，不会在你正在操作时突然锁屏")
                }
                Text(exceptionsHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("自动锁定的例外")
            }

            Section("其他") {
                Toggle("菜单栏图标旁显示状态文字", isOn: $settings.showRSSIInMenuBar)
                    .help("默认只显示图标；开启后在图标旁追加「已解锁 / 已锁定 / 暂停」等文字")
                Toggle("锁定 / 异常时发送通知", isOn: $settings.notificationsEnabled)
                    .help("蓝牙异常、信号丢失等会发通知")
                Toggle("立即锁定前需要确认", isOn: $settings.confirmBeforeLock)
                    .help("开启后点「立即锁定」会先弹确认")
                Toggle("开机启动", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { newValue in
                        settings.launchAtLogin = newValue
                        LaunchManager.setEnabled(newValue)
                    }
                ))
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460)
        // FR-10：设置项与系统登录项的实际状态保持一致。
        .onAppear { settings.launchAtLogin = LaunchManager.isRegistered }
    }

    /// 私有接口是否可用取决于当前系统版本，这里直接展示探测结果（只解析符号，不会锁屏）。
    private var systemLockStatusLabel: some View {
        let available = SystemLockScreen.isAvailable
        return Label(
            available
                ? "已找到系统锁屏接口（仅符号检测，不代表已验证锁屏效果；系统升级后可能失效）"
                : "当前系统上找不到该接口，请改用其他方式",
            systemImage: available ? "exclamationmark.triangle" : "xmark.octagon"
        )
        .font(WLFont.caption)
        .foregroundStyle(available ? WLColor.neutral : WLColor.danger)
    }

    /// 例外项会让「该锁没锁」，把代价写清楚；两项都默认关闭。
    private var exceptionsHint: String {
        "两项默认关闭，开启后在对应场景下会推迟锁屏，请自行权衡。" +
        "「会议」依据是应用持有阻止显示器睡眠的系统断言，具体软件是否都会持有尚未逐一验证；" +
        "用户主动运行的 caffeinate 不计入。"
    }

    private var thresholdHint: String {
        "阈值越接近越容易误锁，已强制保留 \(ThresholdMath.minimumGap) dBm 间隔。" +
        "手表与 iPhone 连接时广播会被系统节流，丢失前信号很强时超时会自动放宽到 " +
        "\(Int(settings.signalLostTimeout * 2.5)) 秒。"
    }

    /// 阈值改动统一过 clamp，避免设出「在身边比已离开还弱」的非法组合。
    private var nearBinding: Binding<Int> {
        Binding(
            get: { settings.nearRSSI },
            set: { apply(near: $0, far: settings.farRSSI) }
        )
    }

    private var farBinding: Binding<Int> {
        Binding(
            get: { settings.farRSSI },
            set: { apply(near: settings.nearRSSI, far: $0) }
        )
    }

    private func apply(near: Int, far: Int) {
        let clamped = ThresholdMath.clamp(near: near, far: far)
        settings.nearRSSI = clamped.near
        settings.farRSSI = clamped.far
    }
}

// MARK: - 关于

private struct AboutPage: View {
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        VStack(spacing: WLSpacing.md) {
            Spacer(minLength: 0)

            BrandLogoView(size: 72)
            Text(BrandLogo.name)
                .font(.title.bold())
            Text("用 Apple Watch 的蓝牙距离自动锁定 / 唤醒 Mac")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(versionText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Divider()
                .frame(width: 240)
                .padding(.vertical, WLSpacing.xs)

            FormCard(subtitle: "换手表、重新授权蓝牙，或想重看一遍说明时，随时可以重跑引导。") {
                HStack(spacing: WLSpacing.sm) {
                    WLButton("重新运行首次启动引导", systemImage: "arrow.counterclockwise", width: 240) {
                        settings.hasCompletedOnboarding = false
                        OnboardingWindow.present(session: AppSession.shared)
                    }
                    .help("重新走一遍授权与绑定流程")
                    Spacer(minLength: 0)
                }
            }
            .frame(width: 320)

            Text("应用不联网、不上传任何数据，全部在本机计算。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(WLSpacing.xl)
    }

    private var versionText: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        if let build, build != short {
            return "版本 \(short)（\(build)）"
        }
        return "版本 \(short)"
    }
}
