import Foundation

/// 信号所处的分区。
///
/// 一律由 `SignalMeter.level` 推出，保证与信号条、判定引擎的口径一致：
/// 4 格 = 在身边（≥ 在身边阈值）；1 格 = 已离开（≤ 已离开阈值）；2~3 格 = 两者之间的过渡区。
enum ProximityZone: Equatable {
    case unknown
    case far
    case transition
    case near

    var title: String {
        switch self {
        case .unknown: return String(localized: "无信号")
        case .far: return String(localized: "已离开")
        case .transition: return String(localized: "过渡区")
        case .near: return String(localized: "在身边")
        }
    }

    /// 当前信号落在哪个分区。RSSI ≥ 0（含 macOS 无有效信号时回传的 127）一律为 `.unknown`。
    static func classify(rssi: Double, nearRSSI: Int, farRSSI: Int) -> ProximityZone {
        switch SignalMeter.level(rssi: rssi, nearRSSI: nearRSSI, farRSSI: farRSSI) {
        case SignalMeter.levelCount: return .near
        case 2, 3: return .transition
        case 1: return .far
        default: return .unknown
        }
    }
}
