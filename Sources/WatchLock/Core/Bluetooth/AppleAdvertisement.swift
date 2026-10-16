import Foundation

/// Apple Continuity 广播（厂商数据）解析。
///
/// 依据：Apple 设备以「随机地址 + IRK」广播，第三方拿不到 IRK，只能从厂商数据里提取特征。
/// 广播线格式已有公开逆向研究（furiousMAC/continuity、PETS 2019《Handoff All Your Privacy》），
/// 布局为：公司 ID `4C 00`（小端 0x004C）+ 消息类型 1 字节 + 声明长度 1 字节 + payload。
///
/// 注意：**这里只解析结构，不给类型字节赋予语义名称**。类型值的具体含义（如哪个是 Nearby Info、
/// 哪个是 Watch 在场广播）需要真机抓包确认后才能固化，见 `docs/anti-false-lock-research.md` §4。
enum AppleAdvertisement {
    /// Bluetooth SIG 分配给 Apple 的公司 ID。
    static let appleCompanyID: UInt16 = 0x004C

    struct Payload: Equatable {
        /// Continuity 消息类型字节。
        let type: UInt8
        /// 广播中声明的 payload 长度（CoreBluetooth 给出的字节可能被截断，故与实际长度分开保存）。
        let declaredLength: UInt8
        let body: [UInt8]

        var isComplete: Bool { body.count == Int(declaredLength) }

        /// 广播类型指纹：**只取类型字节**。
        ///
        /// 真机抓包（2026-10-15，本机 12 秒内 283 台设备）显示：
        /// - payload 里含随时间滚动的内容，不能做指纹；
        /// - 声明长度会随设备状态变化（Apple Watch 与 iPhone 的 Continuity 类型同为 0x10，
        ///   长度却分别观测到 5 与 7，全样本里 0x10 的长度分布在 2~28），把长度纳入指纹会误拒续接；
        /// - 类型字节也不唯一（手表与 iPhone 都是 0x10），因此指纹只作辅助证据，不能单独区分手表。
        var fingerprint: String {
            String(format: "type=0x%02x", type)
        }

        var typeHex: String { String(format: "0x%02x", type) }

        var bodyHex: String {
            body.map { String(format: "%02x", $0) }.joined(separator: " ")
        }
    }

    /// 厂商数据是否来自 Apple。
    static func isApple(_ data: Data?) -> Bool {
        guard let data, data.count >= 2 else { return false }
        return companyID(of: data) == appleCompanyID
    }

    static func companyID(of data: Data) -> UInt16 {
        UInt16(data[data.startIndex]) | (UInt16(data[data.startIndex + 1]) << 8)
    }

    /// 解析 Apple 厂商数据；不是 Apple 数据或长度不足时返回 nil。
    static func parse(_ data: Data?) -> Payload? {
        guard let data, isApple(data), data.count >= 4 else { return nil }
        let bytes = [UInt8](data)
        let type = bytes[2]
        let declaredLength = bytes[3]
        let body = Array(bytes.dropFirst(4))
        return Payload(type: type, declaredLength: declaredLength, body: body)
    }

    /// 前 `limit` 个字节的十六进制，用于抓包与日志（超出部分以 `…` 表示）。
    static func hex(_ data: Data?, limit: Int = 16) -> String? {
        guard let data, !data.isEmpty else { return nil }
        let prefix = data.prefix(limit).map { String(format: "%02x", $0) }
        let suffix = data.count > limit ? " …（共 \(data.count) 字节）" : ""
        return prefix.joined(separator: " ") + suffix
    }

    /// 人可读描述，用于诊断与抓包界面。
    static func describe(_ data: Data?) -> String? {
        guard let data else { return nil }
        guard let payload = parse(data) else {
            return isApple(data) ? "Apple 厂商数据（\(hex(data) ?? "-")，结构不可解析）" : nil
        }
        let truncated = payload.isComplete ? "" : "，实际 \(payload.body.count) 字节（被系统截断）"
        return "Apple Continuity 类型 \(payload.typeHex)，声明 \(payload.declaredLength) 字节\(truncated)：\(payload.bodyHex)"
    }
}
