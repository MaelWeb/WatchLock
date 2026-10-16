import CoreBluetooth
import Foundation

extension CBManagerState {
    /// 蓝牙状态的人可读描述（诊断界面用）。
    var title: String {
        switch self {
        case .unknown: return "未知"
        case .resetting: return "重置中"
        case .unsupported: return "不支持"
        case .unauthorized: return "未授权"
        case .poweredOff: return "已关闭"
        case .poweredOn: return "已开启"
        @unknown default: return "未知"
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
        case .unknown: return "正在搜索手表…"
        case .near: return "手表在身边"
        case .far: return "手表已离开"
        case .paused: return "已暂停自动锁定"
        case .disabled: return "自动锁定已关闭"
        }
    }

    var shortTitle: String {
        switch self {
        case .unknown: return "搜索中"
        case .near: return "已解锁"
        case .far: return "已锁定"
        case .paused: return "暂停"
        case .disabled: return "关闭"
        }
    }

    var symbolName: String {
        switch self {
        case .unknown: return "wave.3.right.circle"
        case .near: return "lock.open.rotation"
        case .far: return "lock.circle"
        case .paused: return "pause.circle"
        case .disabled: return "poweroff.circle"
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

    var displayName: String {
        name.isEmpty ? "未命名设备" : name
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
            parts.append("命中=\(matchReasons.sorted().joined(separator: ","))")
        }
        return parts.joined(separator: "  ")
    }
}

extension DiscoveredWatch {
    /// 合并「强候选」与「信号最强的若干台」，去重后按 RSSI 降序（纯函数，便于测试）。
    ///
    /// 存在的意义：Apple 邻近广播绝大多数不带名称，靠名字判断是否手表并不可靠；
    /// 但「离 Mac 最近」这一点在任何广播形态下都成立，因此把信号最强的设备也纳入可选列表。
    static func mergedBindingList(
        strong: [DiscoveredWatch],
        all: [DiscoveredWatch],
        limit: Int
    ) -> [DiscoveredWatch] {
        var seen = Set<UUID>()
        var result: [DiscoveredWatch] = []

        for device in strong where seen.insert(device.id).inserted {
            result.append(device)
        }
        for device in all.sorted(by: { $0.rssi > $1.rssi }).prefix(limit)
        where seen.insert(device.id).inserted {
            var copy = device
            if copy.matchReasons.isEmpty {
                copy.matchReasons = ["靠近 Mac（按信号排序）"]
            }
            result.append(copy)
        }
        return result.sorted { $0.rssi > $1.rssi }
    }
}

/// 距离估算结果。
struct ProximitySample {
    let smoothedRSSI: Double
    let estimatedDistance: Double
    let date: Date
}
