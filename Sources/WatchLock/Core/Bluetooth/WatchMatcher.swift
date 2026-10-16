import CoreBluetooth
import Foundation

/// 判断一个 BLE 外设是否可能是 Apple Watch。
///
/// 说明：Apple Watch 的广播内容在不同 watchOS / 配对状态下并不稳定，
/// 因此这里采用「多证据加权」的方式，最终绑定仍需用户在设备列表里确认。
enum WatchMatcher {
    /// 已知与 Apple Watch / Apple 连续性功能相关的服务 UUID。
    static let appleRelatedServiceUUIDs: Set<CBUUID> = [
        CBUUID(string: "7905F431-B5CE-4E99-A40F-4B1E122D00D0"), // Apple Notification Center Service
        CBUUID(string: "89D3502B-0F36-433A-8EF4-C502AD55F8DC"), // Apple Media Service
        CBUUID(string: "D0611E78-BBB4-4591-A5F8-487910AE4366")  // Continuity / Nearby
    ]

    /// Apple Watch 广播名里的空格常是 U+00A0（不间断空格），必须归一化后再匹配。
    private static func normalized(_ text: String) -> String {
        text.lowercased().map { character in
            switch character {
            case "\u{00A0}", "\u{202F}", "\u{2007}", "\u{2009}": return " "
            default: return String(character)
            }
        }.joined()
    }

    struct Result {
        let isCandidate: Bool
        /// 强候选：证据足够可信，直接进绑定列表。
        /// 仅「厂商数据为 Apple」属于弱证据，周围常有上百台 Apple 设备，只出现在诊断列表里。
        let isStrongCandidate: Bool
        let reasons: Set<String>
    }

    static func evaluate(
        name: String?,
        serviceUUIDs: [CBUUID],
        manufacturerData: Data?,
        boundIdentifier: UUID?,
        peripheralIdentifier: UUID
    ) -> Result {
        var reasons: Set<String> = []
        var isStrong = false

        if let boundIdentifier, boundIdentifier == peripheralIdentifier {
            reasons.insert("已绑定设备")
            isStrong = true
        }

        if let name {
            let lowered = Self.normalized(name)
            if lowered.contains("apple watch") {
                reasons.insert("名称匹配 Apple Watch")
                isStrong = true
            } else if lowered.contains("watch") {
                reasons.insert("名称包含 watch")
            }
        }

        let matchedServices = Set(serviceUUIDs).intersection(appleRelatedServiceUUIDs)
        if !matchedServices.isEmpty {
            reasons.insert("命中 Apple 服务 UUID")
            isStrong = true
        }

        // 厂商数据的证据强度：任何 Apple 设备（iPhone / 耳机 / 邻居的电脑）都会带 4C 00，
        // 因此只作为弱证据。但解析出 Continuity 类型字节后，至少能把「Broadcast 类型」记录下来，
        // 供真机抓包固化识别规则（`docs/anti-false-lock-research.md` §4）。
        if let payload = AppleAdvertisement.parse(manufacturerData) {
            var text = "Apple Continuity 广播（类型 \(payload.typeHex)，声明 \(payload.declaredLength) 字节"
            if !payload.isComplete { text += "，实际 \(payload.body.count) 字节" }
            reasons.insert(text + "）")
        } else if AppleAdvertisement.isApple(manufacturerData) {
            reasons.insert("厂商数据为 Apple")
        }

        return Result(
            isCandidate: !reasons.isEmpty,
            isStrongCandidate: isStrong,
            reasons: reasons
        )
    }

    /// 蓝牙地址轮换（RPA）后是否应把绑定关系迁移到新地址。
    ///
    /// 依据：Apple 开发者论坛有报告指出，未绑定 BLE 外设的 `CBPeer.identifier` 在系统升级
    /// 与设备重启后会变化（iOS 27 起可稳定复现）；第三方又拿不到用于解析随机地址的 IRK，
    /// 只能退而求其次用「名称一致」来续接。
    /// 若不续接，样本会被当成「非绑定设备」丢弃，进而误判为信号丢失并锁屏。
    /// 详见 `docs/anti-false-lock-research.md` 证据 1。
    /// - Parameters:
    ///   - boundAdvertisement: 绑定时记录的广播类型指纹（见 `AppleAdvertisement.Payload.fingerprint`）。
    ///   - candidateManufacturerData: 候选设备当前的厂商数据。
    ///   两者都能解析且不一致时拒绝续接，避免「同名但不同类广播」的设备顶替已绑定手表。
    static func shouldRebind(
        boundIdentifier: String?,
        boundName: String?,
        candidateIdentifier: UUID,
        candidateName: String,
        boundAdvertisement: String? = nil,
        candidateManufacturerData: Data? = nil
    ) -> Bool {
        guard let boundIdentifier,
              let boundUUID = UUID(uuidString: boundIdentifier),
              boundUUID != candidateIdentifier else { return false }
        guard let boundName, !boundName.isEmpty, !candidateName.isEmpty else { return false }
        guard normalized(boundName) == normalized(candidateName) else { return false }

        // 指纹只在能解析出来时才参与判断：解析不出来就退回「仅凭名称」，避免过度拒绝导致误锁。
        guard let boundAdvertisement,
              let candidate = AppleAdvertisement.parse(candidateManufacturerData)?.fingerprint
        else { return true }
        return boundAdvertisement == candidate
    }
}
