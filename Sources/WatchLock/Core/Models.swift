import CoreBluetooth
import Foundation

extension CBManagerState {
    /// 蓝牙状态的人可读描述（诊断界面用）。
    var title: String {
        switch self {
        case .unknown: return String(localized: "未知")
        case .resetting: return String(localized: "重置中")
        case .unsupported: return String(localized: "不支持")
        case .unauthorized: return String(localized: "未授权")
        case .poweredOff: return String(localized: "已关闭")
        case .poweredOn: return String(localized: "已开启")
        @unknown default: return String(localized: "未知")
        }
    }
}

/// 与手表之间的相对位置状态。
enum ProximityStatus: String, CaseIterable, Identifiable {
    case unknown
    case near
    case far
    case paused
    case disabled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unknown: return String(localized: "正在搜索手表…")
        case .near: return String(localized: "手表在身边")
        case .far: return String(localized: "手表已离开")
        case .paused: return String(localized: "已暂停自动锁定")
        case .disabled: return String(localized: "自动锁定已关闭")
        }
    }

    var shortTitle: String {
        switch self {
        case .unknown: return String(localized: "搜索中")
        case .near: return String(localized: "已解锁")
        case .far: return String(localized: "已锁定")
        case .paused: return String(localized: "暂停")
        case .disabled: return String(localized: "关闭")
        }
    }
}

/// 蓝牙扫描发现的候选设备。
struct DiscoveredWatch: Identifiable, Hashable {
    let id: UUID
    var name: String
    var rssi: Int
    var lastSeen: Date
    /// 命中的识别依据（名称 / 服务 UUID / 厂商数据），用于诊断页展示。
    var matchReasons: Set<String>
    /// 广播中的服务 UUID（用于「搜不到手表」时诊断）。
    var serviceUUIDs: Set<String> = []
    /// 广播中的厂商数据原始内容。
    var manufacturerData: Data?
    /// 从 Proximity Pairing 广播（或同一设备更早的广播缓存）识别出的 AirPods 型号。
    var airPodsModel: AirPodsModel?

    var displayName: String {
        name.isEmpty ? String(localized: "未命名设备") : name
    }

    /// 广播内容摘要，供调试列表展示 / 复制诊断信息。
    var advertisementSummary: String {
        var parts: [String] = []
        parts.append("id=\(id.uuidString.prefix(8))")
        parts.append("name=\(name.isEmpty ? "-" : name)")
        if !serviceUUIDs.isEmpty {
            parts.append("svc=\(serviceUUIDs.sorted().joined(separator: ","))")
        }
        if let manufacturerData {
            parts.append("manu=\(manufacturerData.map { String(format: "%02x", $0) }.joined(separator: " "))")
        }
        if !matchReasons.isEmpty {
            parts.append(String(localized: "命中=\(matchReasons.sorted().joined(separator: ","))"))
        }
        return parts.joined(separator: "  ")
    }
}

extension DiscoveredWatch {
    /// 「按信号排序」入选时补上的识别依据（没有任何其他依据的设备）。
    static let nearMacReason = String(localized: "靠近 Mac（按信号排序）")

    /// 排序用的信号强度：RSSI ≥ 0（含哨兵值 127）表示「未知」，必须当作最弱，
    /// 否则它们会因为数值大而排到最前面。
    var rankingRSSI: Int { rssi < 0 ? rssi : Self.unknownRankingRSSI }
    static let unknownRankingRSSI = -127

    /// 信号强到弱排序；信号相同时按标识排，保证每次结果一致（字典遍历顺序是随机的，
    /// 不加平局规则的话，同信号的设备每次刷新顺序都会变）。
    static func isRankedBefore(_ lhs: DiscoveredWatch, _ rhs: DiscoveredWatch) -> Bool {
        if lhs.rankingRSSI != rhs.rankingRSSI { return lhs.rankingRSSI > rhs.rankingRSSI }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// 合并「强候选」与「信号最强的若干台」，去重后按信号降序（纯函数，便于测试）。
    ///
    /// 存在的意义：Apple 邻近广播绝大多数不带名称，靠名字判断是否手表并不可靠；
    /// 但「离 Mac 最近」这一点在任何广播形态下都成立，因此把信号最强的设备也纳入可选列表。
    static func mergedBindingList(
        strong: [DiscoveredWatch],
        all: [DiscoveredWatch],
        limit: Int,
        admissionOrder: (DiscoveredWatch, DiscoveredWatch) -> Bool = DiscoveredWatch.isRankedBefore
    ) -> [DiscoveredWatch] {
        var seen = Set<UUID>()
        var result: [DiscoveredWatch] = []

        for device in strong where seen.insert(device.id).inserted {
            result.append(device)
        }
        for device in all.sorted(by: admissionOrder).prefix(limit)
        where seen.insert(device.id).inserted {
            var copy = device
            if copy.matchReasons.isEmpty {
                copy.matchReasons = [nearMacReason]
            }
            result.append(copy)
        }
        return result.sorted(by: isRankedBefore)
    }
}

/// 距离估算结果。
struct ProximitySample {
    let smoothedRSSI: Double
    let estimatedDistance: Double
    let date: Date
}
