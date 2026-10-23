import Foundation

/// 用户对某台设备的手动覆盖：名称与图标类别，两者都可以只设其一。
struct DeviceOverride: Codable, Equatable {
    var name: String?
    var kind: DeviceKind?

    /// 名称与图标都没设，等同于没有覆盖。
    var isEmpty: Bool { name == nil && kind == nil }

    /// 名称长度上限：只用于界面展示，过长会撑坏一行。
    static let maxNameLength = 40

    /// 清洗用户输入：名称去首尾空白并截断，空白名称视为未设置。
    func normalized() -> DeviceOverride {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return DeviceOverride(
            name: trimmed.isEmpty ? nil : String(trimmed.prefix(Self.maxNameLength)),
            kind: kind
        )
    }
}

/// 设备在界面上的最终呈现（名称 + 图标）。
struct DeviceLabel: Equatable {
    /// 展示名称；没有任何真实名称时是「型号或未命名设备 · 标识前 8 位」。
    let name: String
    let kind: DeviceKind
    /// 是否有真实名称（用户命名 / 绑定快照 / 广播名），用于判断要不要在界面上提示「可以自己命名」。
    let hasRealName: Bool
}

/// 决定设备「叫什么、用什么图标」的纯函数集合，便于单元测试。
enum DeviceNaming {
    /// 绑定无名设备时写入的占位名（标识前 8 位）。它不是真实名称，不能当作快照优先显示。
    static func isPlaceholder(_ name: String, id: String) -> Bool {
        name.caseInsensitiveCompare(String(id.prefix(8))) == .orderedSame
    }

    /// 绑定 / 添加那一刻要记录的名称快照：有名称用名称，其次 AirPods 型号，最后是标识前 8 位占位。
    static func snapshotName(name: String, model: AirPodsModel?, id: String) -> String {
        if !name.isEmpty { return name }
        if let model { return model.displayName }
        return String(id.prefix(8))
    }

    /// 解析最终呈现。
    ///
    /// 名称优先级：用户自定义 > 绑定 / 添加时的快照 > 实时广播名 > 型号名。
    /// 快照排在实时名之前，是因为广播名时有时无，已选中的设备不应该在列表里闪成「未命名设备」。
    ///
    /// 图标优先级：用户选择 > AirPods 型号 > 按名称推断 > `fallbackKind`。
    /// - Parameters:
    ///   - id: 外设标识（`UUID.uuidString`）。
    ///   - snapshotName: 仅已绑定 / 已选为辅助的设备有。
    ///   - fallbackKind: 什么都认不出来时用的图标；已绑定的手表传 `.watch`。
    static func resolve(
        id: String,
        liveName: String,
        model: AirPodsModel?,
        snapshotName: String?,
        snapshotModel: AirPodsModel? = nil,
        override: DeviceOverride?,
        fallbackKind: DeviceKind = .unknown
    ) -> DeviceLabel {
        let custom = clean(override?.name)
        let snapshot = clean(snapshotName).flatMap { isPlaceholder($0, id: id) ? nil : $0 }
        let live = clean(liveName)
        let resolvedModel = model ?? snapshotModel
        let realName = custom ?? snapshot ?? live

        let name = realName
            ?? "\(resolvedModel?.displayName ?? String(localized: "未命名设备")) · \(id.prefix(8))"

        let kind: DeviceKind
        if let chosen = override?.kind {
            kind = chosen
        } else if let resolvedModel {
            kind = resolvedModel.kind
        } else {
            kind = [custom, snapshot, live]
                .compactMap { $0 }
                .map(DeviceKind.infer(fromName:))
                .first { $0 != .unknown } ?? fallbackKind
        }
        return DeviceLabel(name: name, kind: kind, hasRealName: realName != nil)
    }

    private static func clean(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
