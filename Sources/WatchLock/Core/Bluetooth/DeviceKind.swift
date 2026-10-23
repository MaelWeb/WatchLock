import Foundation

/// 蓝牙设备的大类，仅用于界面选择图标。
///
/// 只能依据广播名称判断：Apple Continuity 的类型字节在手表与 iPhone 之间并不唯一
/// （见 `AppleAdvertisement.Payload.fingerprint`），无法用来区分设备类型。
/// 因此无名或无法识别的设备一律归为 `.unknown`，宁可显示通用图标也不猜错。
enum DeviceKind: String, Codable, CaseIterable, Equatable {
    case watch
    case iPhone
    case iPad
    case laptop
    case desktop
    case airPods
    case airPodsPro
    case airPodsMax
    case headphones
    case homePod
    case appleTV
    case keyboard
    case mouse
    case unknown

    /// 手动选择图标时展示的名称（`unknown` 不出现在选择列表里，见 `selectableKinds`）。
    var title: String {
        switch self {
        case .watch: return String(localized: "手表")
        case .iPhone: return "iPhone"
        case .iPad: return "iPad"
        case .laptop: return String(localized: "笔记本电脑")
        case .desktop: return String(localized: "台式电脑")
        case .airPods: return "AirPods"
        case .airPodsPro: return "AirPods Pro"
        case .airPodsMax: return "AirPods Max"
        case .headphones: return String(localized: "耳机")
        case .homePod: return "HomePod"
        case .appleTV: return "Apple TV"
        case .keyboard: return String(localized: "键盘")
        case .mouse: return String(localized: "鼠标")
        case .unknown: return String(localized: "其他设备")
        }
    }

    /// 手动选择图标时可选的类别：「其他设备」就是不选，所以不放进列表。
    static var selectableKinds: [DeviceKind] { allCases.filter { $0 != .unknown } }

    /// 对应的 SF Symbol 名称。
    var symbolName: String {
        switch self {
        case .watch: return "applewatch"
        case .iPhone: return "iphone"
        case .iPad: return "ipad"
        case .laptop: return "laptopcomputer"
        case .desktop: return "desktopcomputer"
        case .airPods: return "airpods"
        case .airPodsPro: return "airpodspro"
        case .airPodsMax: return "airpodsmax"
        case .headphones: return "headphones"
        case .homePod: return "homepod"
        case .appleTV: return "appletv"
        case .keyboard: return "keyboard"
        case .mouse: return "computermouse"
        case .unknown: return "dot.radiowaves.left.and.right"
        }
    }

    /// 根据广播名称推断设备类型；匹配顺序即优先级（更具体的型号在前）。
    static func infer(fromName name: String) -> DeviceKind {
        let text = WatchMatcher.normalized(name)
        guard !text.isEmpty else { return .unknown }

        // 顺序敏感：「airpods pro」「airpods max」必须先于「airpods」，
        // 「macbook」必须先于「mac」类台式机关键字，避免被更宽泛的规则吞掉。
        let rules: [(keywords: [String], kind: DeviceKind)] = [
            (["apple watch", "watch"], .watch),
            (["airpods pro"], .airPodsPro),
            (["airpods max"], .airPodsMax),
            (["airpods"], .airPods),
            (["beats", "headphone", "buds"], .headphones),
            (["iphone"], .iPhone),
            (["ipad"], .iPad),
            (["macbook"], .laptop),
            (["imac", "mac mini", "mac studio", "mac pro"], .desktop),
            (["homepod"], .homePod),
            (["apple tv"], .appleTV),
            (["keyboard"], .keyboard),
            (["mouse", "trackpad"], .mouse)
        ]
        return rules.first { rule in rule.keywords.contains { text.contains($0) } }?.kind ?? .unknown
    }
}
