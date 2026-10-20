import SwiftUI

/// 解锁页：靠近时的行为 + 解锁策略 + 托管密码（高风险）。
struct UnlockPage: View {
    @ObservedObject private var settings = SettingsStore.shared

    @State private var password: String = ""
    @State private var message: String?
    @State private var isMessageError = false
    @State private var confirmingClear = false

    var body: some View {
        Form {
            Section("靠近时的行为") {
                Toggle("点亮显示器", isOn: $settings.wakeDisplayOnApproach)
                    .help("回到 Mac 旁边时唤醒屏幕，解锁交给系统")
                Picker("解锁策略", selection: $settings.unlockStrategy) {
                    ForEach(UnlockStrategy.allCases) { strategy in
                        Text(strategy.title).tag(strategy)
                    }
                }
                .help("推荐使用系统自带的「使用 Apple Watch 解锁」")
                Text(settings.unlockStrategy.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ValueStepperRow(
                    title: String(localized: "唤醒后宽限"),
                    value: $settings.unlockGraceAfterWake,
                    range: 0 ... 30,
                    valueText: ValueFormat.seconds(settings.unlockGraceAfterWake),
                    help: String(localized: "刚唤醒的一小段时间内不判定为离开，避免刚唤醒就误锁")
                )
            }

            Section {
                WLButton(String(localized: "打开「系统设置 → 锁定屏幕」"), systemImage: "arrow.up.forward.app") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension")!)
                }
                .help("在系统设置里开启「使用 Apple Watch 解锁」")
                Text("Apple 未提供第三方可用的自动解锁 API，推荐开启系统自带的「使用 Apple Watch 解锁」，本应用负责靠近时唤醒屏幕。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("系统自动解锁")
            }

            Section {
                if settings.unlockStrategy == .managedPassword {
                    SecureField("macOS 登录密码", text: $password)
                        .textContentType(.password)
                        .help("仅保存在本机钥匙串，不会同步或上传")
                    HStack(spacing: WLSpacing.sm) {
                        WLButton(String(localized: "保存到钥匙串"), systemImage: "key.fill", role: .primary) { save() }
                            .help("以「仅本机解锁时可访问」的方式写入钥匙串")
                        WLButton(String(localized: "清除"), systemImage: "trash", role: .danger) { confirmingClear = true }
                            .help("删除钥匙串中已保存的登录密码")
                        Spacer(minLength: 0)
                    }
                    WLButton(String(localized: "打开辅助功能授权"), systemImage: "hand.raised") {
                        _ = AccessibilityProbe.isTrusted(prompt: true)
                    }
                    .help("模拟键入解锁密码需要辅助功能权限")
                    if let message {
                        Label(message, systemImage: isMessageError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(isMessageError ? WLColor.danger : WLColor.success)
                    }
                    Text("密码将以「仅本机解锁时可访问」的方式存入钥匙串，并通过辅助功能模拟键入。系统更新或登录窗口结构变化时可能失效。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("当前策略不需要密码。若确实要让应用代为输入登录密码，请把上方「解锁策略」改为「\(UnlockStrategy.managedPassword.title)」。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Label("托管密码（高风险）", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(WLColor.warning)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460)
        .confirmationDialog("清除钥匙串中保存的登录密码？", isPresented: $confirmingClear) {
            Button("清除", role: .destructive) { clear() }
            Button("取消", role: .cancel) {}
        }
    }

    private func save() {
        do {
            try KeychainStore().savePassword(password)
            message = String(localized: "已保存到钥匙串")
            isMessageError = false
            password = ""
        } catch {
            message = error.localizedDescription
            isMessageError = true
        }
    }

    private func clear() {
        do {
            try KeychainStore().deletePassword()
            message = String(localized: "已清除")
            isMessageError = false
        } catch {
            message = error.localizedDescription
            isMessageError = true
        }
    }
}
