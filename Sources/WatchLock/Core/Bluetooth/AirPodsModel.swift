import Foundation

/// 可从 Apple Proximity Pairing 广播中识别出的耳机型号。
///
/// 数据来源是社区对 Continuity 协议的逆向研究（furiousMAC/continuity、OpenPods、LibrePods 等），
/// **尚未在本项目的真机抓包里逐一核对**：`docs/anti-false-lock-research.md` 只记录过类型字节 `0x07`
/// 出现过 11 次，没有把它们对应到具体设备。所以这里的策略是「表里有才认，不在表里就不猜」，
/// 表外的型号一律回退到名称推断 / 通用图标。
enum AirPodsModel: String, Codable, CaseIterable {
    case airPods1
    case airPods2
    case airPods3
    case airPods4
    case airPodsPro
    case airPodsPro2
    case airPodsPro2USBC
    case airPodsMax

    /// 广播里的 16 位型号 ID（大端）。
    init?(modelID: UInt16) {
        switch modelID {
        case 0x0220: self = .airPods1
        case 0x0F20: self = .airPods2
        case 0x1320: self = .airPods3
        case 0x1920: self = .airPods4
        case 0x0E20: self = .airPodsPro
        case 0x1420: self = .airPodsPro2
        case 0x2420: self = .airPodsPro2USBC
        case 0x0A20: self = .airPodsMax
        default: return nil
        }
    }

    /// 型号名称是产品名，不随界面语言翻译。
    var displayName: String {
        switch self {
        case .airPods1: return "AirPods"
        case .airPods2: return "AirPods (2nd generation)"
        case .airPods3: return "AirPods (3rd generation)"
        case .airPods4: return "AirPods 4"
        case .airPodsPro: return "AirPods Pro"
        case .airPodsPro2: return "AirPods Pro (2nd generation)"
        case .airPodsPro2USBC: return "AirPods Pro (2nd generation, USB-C)"
        case .airPodsMax: return "AirPods Max"
        }
    }

    /// 对应的图标类别。
    var kind: DeviceKind {
        switch self {
        case .airPods1, .airPods2, .airPods3, .airPods4: return .airPods
        case .airPodsPro, .airPodsPro2, .airPodsPro2USBC: return .airPodsPro
        case .airPodsMax: return .airPodsMax
        }
    }
}

extension AppleAdvertisement {
    /// Continuity 的 Proximity Pairing 消息类型（公开研究给出的值，见 `AirPodsModel` 的说明）。
    static let proximityPairingType: UInt8 = 0x07

    /// 从厂商数据里读取 AirPods 型号；不是 Proximity Pairing、结构不对或型号不在表内时返回 nil。
    ///
    /// 布局（公开研究）：payload 以前缀字节 `0x01` 开头，随后 2 字节是大端型号 ID。
    /// 只要求前 3 个字节存在，CoreBluetooth 截断后面的内容也不影响识别。
    static func airPodsModel(from data: Data?) -> AirPodsModel? {
        guard let payload = parse(data),
              payload.type == proximityPairingType,
              payload.body.count >= 3,
              payload.body[0] == 0x01 else { return nil }
        let modelID = UInt16(payload.body[1]) << 8 | UInt16(payload.body[2])
        return AirPodsModel(modelID: modelID)
    }
}
