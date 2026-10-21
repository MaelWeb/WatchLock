import Darwin
import Foundation
import SystemConfiguration

/// 读取当前网络环境（默认网关 MAC，可选 SSID）。
///
/// 读取方式与依据见 `TrustedPlace` 的注释（2026-10-20 本机实测）：
/// - 默认网关 IP：`SCDynamicStore` 的 `State:/Network/Global/IPv4` → `Router`，无需授权；
/// - 网关 MAC：`sysctl(CTL_NET, PF_ROUTE, NET_RT_FLAGS, RTF_LLINFO)` 读内核 ARP 表，无需 root、
///   不发包、不触发「本地网络」提示（只读内核已有的表）。网关还没被解析过时表里可能没有它，
///   此时返回 `nil`，调用方等下一轮即可；
/// - SSID：`CWWiFiClient`，只有用户授予定位权限且系统愿意返回时才有值，失败一律当作「没有」。
enum NetworkProbe {
    /// 当前网络快照。读不到时字段为 `nil`，不会抛错。
    static func snapshot(includeSSID: Bool) -> TrustedPlace.Snapshot {
        let mac = defaultGatewayIP().flatMap { gatewayMAC(forIP: $0) }
        let ssid = includeSSID && mac != nil ? currentSSID() : nil
        return .init(gatewayMAC: mac, ssid: ssid)
    }

    // MARK: - 默认网关

    static func defaultGatewayIP() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "WatchLock.NetworkProbe" as CFString, nil, nil),
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let router = global["Router"] as? String, !router.isEmpty else { return nil }
        return router
    }

    // MARK: - ARP 表

    /// 从内核 ARP 表里取 `ip` 对应的 MAC（已归一化）。
    static func gatewayMAC(forIP ip: String) -> String? {
        TrustedPlace.normalizeMAC(arpTable().first(where: { $0.ip == ip })?.mac)
    }

    struct ARPEntry: Equatable {
        let ip: String
        let mac: String
    }

    static func arpTable() -> [ARPEntry] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return [] }
        return parseARP(buffer, length: length)
    }

    /// 解析 `NET_RT_FLAGS` 返回的路由消息序列（纯函数，便于喂构造数据做单测）。
    ///
    /// 每条消息 = `rt_msghdr` + 目的地址 `sockaddr_in` + 链路层地址 `sockaddr_dl`，
    /// 各 sockaddr 按 4 字节对齐。任何一段越界都直接放弃这条消息，不崩溃。
    static func parseARP(_ buffer: [UInt8], length: Int) -> [ARPEntry] {
        var entries: [ARPEntry] = []
        var offset = 0
        let header = MemoryLayout<rt_msghdr>.size
        func align4(_ n: Int) -> Int { (n + 3) & ~3 }

        while offset + header <= length {
            let messageLength = buffer.withUnsafeBytes {
                Int($0.loadUnaligned(fromByteOffset: offset, as: rt_msghdr.self).rtm_msglen)
            }
            guard messageLength >= header, offset + messageLength <= length else { break }
            defer { offset += messageLength }

            var cursor = offset + header
            let end = offset + messageLength
            guard cursor + MemoryLayout<sockaddr_in>.size <= end else { continue }
            let sin = buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: cursor, as: sockaddr_in.self) }
            guard sin.sin_family == sa_family_t(AF_INET) else { continue }

            var address = sin.sin_addr
            var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &address, &text, socklen_t(INET_ADDRSTRLEN)) != nil else { continue }
            let ip = String(cString: text)

            cursor += align4(Int(sin.sin_len))
            // sockaddr_dl 头：len(1) family(1) index(2) type(1) nlen(1) alen(1) slen(1) = 8 字节，后接 [接口名][链路地址]。
            guard cursor + 8 <= end else { continue }
            let nameLength = Int(buffer[cursor + 5])
            let addressLength = Int(buffer[cursor + 6])
            let macStart = cursor + 8 + nameLength
            guard addressLength == 6, macStart + 6 <= end else { continue }
            let mac = (0 ..< 6).map { String(format: "%02x", buffer[macStart + $0]) }.joined(separator: ":")
            entries.append(.init(ip: ip, mac: mac))
        }
        return entries
    }

    // MARK: - SSID（可选）

    static func currentSSID() -> String? {
        // 未授权时返回 nil，不是错误；这里不主动请求授权，授权入口在设置页。
        let ssid = CWWiFiClientBridge.ssid()
        return (ssid?.isEmpty == false) ? ssid : nil
    }
}
