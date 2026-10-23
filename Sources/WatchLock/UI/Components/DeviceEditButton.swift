import SwiftUI

/// 在任意视图上挂「自定义名称和图标」弹窗。
extension View {
    func deviceEditorPopover(isPresented: Binding<Bool>, deviceID: String, currentName: String) -> some View {
        modifier(DeviceEditorPopover(isPresented: isPresented, deviceID: deviceID, currentName: currentName))
    }
}

private struct DeviceEditorPopover: ViewModifier {
    @EnvironmentObject private var session: AppSession
    @ObservedObject private var settings = SettingsStore.shared

    @Binding var isPresented: Bool
    let deviceID: String
    let currentName: String

    func body(content: Content) -> some View {
        content.popover(isPresented: $isPresented, arrowEdge: .bottom) {
            DeviceEditor(
                placeholder: currentName,
                initial: settings.deviceOverrides[deviceID]
            ) { result in
                session.setDeviceOverride(result, for: deviceID)
                isPresented = false
            } onCancel: {
                isPresented = false
            }
        }
    }
}

/// 行内的「自定义名称和图标」入口（已绑定卡片、已选辅助设备等仍是一行一个的地方）。
struct DeviceEditButton: View {
    /// 外设标识（`UUID.uuidString`）。
    let deviceID: String
    /// 当前展示的名称，作为输入框的占位提示。
    let currentName: String

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "pencil")
        }
        .buttonStyle(.borderless)
        .help("自定义名称和图标")
        .accessibilityLabel("自定义名称和图标")
        .deviceEditorPopover(isPresented: $isPresented, deviceID: deviceID, currentName: currentName)
    }
}

/// 名称 + 图标的编辑表单。名称留空 / 图标选「自动」就是回到自动识别。
struct DeviceEditor: View {
    let placeholder: String
    let onSave: (DeviceOverride?) -> Void
    let onCancel: () -> Void

    @State private var name: String
    /// nil 表示「自动」（按名称 / 型号推断）。
    @State private var kind: DeviceKind?

    init(
        placeholder: String,
        initial: DeviceOverride?,
        onSave: @escaping (DeviceOverride?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.placeholder = placeholder
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: initial?.name ?? "")
        _kind = State(initialValue: initial?.kind)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WLSpacing.md) {
            Text("自定义设备")
                .font(.headline)

            VStack(alignment: .leading, spacing: WLSpacing.xs) {
                Text("名称").font(.caption).foregroundStyle(.secondary)
                TextField(placeholder, text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
            }

            VStack(alignment: .leading, spacing: WLSpacing.xs) {
                Text("图标").font(.caption).foregroundStyle(.secondary)
                Picker("图标", selection: $kind) {
                    Text("自动").tag(DeviceKind?.none)
                    Divider()
                    ForEach(DeviceKind.selectableKinds, id: \.self) { option in
                        Label(option.title, systemImage: option.symbolName).tag(DeviceKind?.some(option))
                    }
                }
                .labelsHidden()
            }

            HStack(spacing: WLSpacing.sm) {
                Button("恢复默认") { onSave(nil) }
                    .buttonStyle(.borderless)
                    .help("清除自定义名称和图标，回到自动识别")
                Spacer(minLength: WLSpacing.sm)
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("保存", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(WLSpacing.lg)
        .frame(width: 280)
    }

    private func save() {
        onSave(DeviceOverride(name: name, kind: kind))
    }
}
