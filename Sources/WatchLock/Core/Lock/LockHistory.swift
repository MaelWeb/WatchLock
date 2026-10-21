import Foundation

/// 锁定记录（FR-21）：每次**真正执行**的锁定留一条（时间 · 原因 · 信号 · 距离 · 是否被标记误锁）。
///
/// 与诊断日志的区别：诊断日志是给排查问题的流水（300 条环形、重启后只能看磁盘文件），
/// 这里是给人看的「它什么时候、为什么锁了我的 Mac」，重启后仍在，可导出 CSV
/// （满足 NFR-07「所有锁定动作可追溯」）。数据只存在本机，不上传。
///
/// 这个文件只放纯逻辑（追加 / 截断 / 误锁标记 / CSV），读写磁盘见 `LockHistoryStore`。
enum LockHistory {
    /// 最多保留的记录条数；超出时丢弃最旧的。
    static let capacity = 200

    struct Record: Codable, Identifiable, Equatable {
        /// 锁定的来源。原始值同时是 CSV 里的取值，**不要改名**（导出文件的使用者会按它过滤）。
        enum Kind: String, Codable {
            /// 状态机判定离开（含信号丢失）后的自动锁定；计入误锁反馈 / 自动调参样本。
            case automatic
            /// 用户点了「立即锁定」。
            case manual
            /// 「手动解锁后重新布防」触发的锁定；与距离阈值无关，不计入调参样本。
            case rearm

            var title: String {
                switch self {
                case .automatic: return String(localized: "自动")
                case .manual: return String(localized: "手动")
                case .rearm: return String(localized: "重新布防")
                }
            }
        }

        var id = UUID()
        var date: Date
        var kind: Kind
        var reason: String
        /// 锁定时最近一次平滑后的信号强度（dBm）。手表失联时这是失联前的最后读数；还没有任何有效读数时为 `nil`。
        var rssi: Int?
        /// 与 `rssi` 同一时刻估算的距离（米）；未知时为 `nil`。
        var distance: Double?
        /// 用户是否把这次标记为误锁。
        var markedFalse = false
    }

    /// 追加一条记录，只保留最新的 `capacity` 条。
    static func appending(_ record: Record, to records: [Record], capacity: Int = capacity) -> [Record] {
        var next = records
        next.append(record)
        if next.count > capacity { next.removeFirst(next.count - capacity) }
        return next
    }

    /// 把**最近一次**自动锁定标记为误锁。
    ///
    /// 只看最近一条自动锁定（与菜单栏「刚才这次是误锁？」的语义一致）；它已经被标记、
    /// 或距今超过 `window` 时不做任何改动，返回 `nil`。
    static func markingLatestAutomaticAsFalse(
        in records: [Record],
        now: Date,
        window: TimeInterval
    ) -> [Record]? {
        guard let index = records.lastIndex(where: { $0.kind == .automatic }) else { return nil }
        let record = records[index]
        guard !record.markedFalse, now.timeIntervalSince(record.date) <= window else { return nil }
        var next = records
        next[index].markedFalse = true
        return next
    }

    // MARK: - 导出

    /// 导出为 CSV（RFC 4180：含逗号 / 引号 / 换行的字段加引号，引号写成两个）。
    ///
    /// 列名与 `kind` 取值固定为英文，便于脚本处理；时间为带时区的 ISO 8601，避免跨时区解读歧义。
    static func csv(_ records: [Record], timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = timeZone

        let header = "time,kind,reason,rssi_dbm,distance_m,marked_false"
        let rows = records.map { record -> String in
            [
                formatter.string(from: record.date),
                record.kind.rawValue,
                record.reason,
                record.rssi.map(String.init) ?? "",
                record.distance.map { String(format: "%.1f", $0) } ?? "",
                record.markedFalse ? "true" : "false",
            ]
            .map(escape)
            .joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\r\n") + "\r\n"
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - 读数换算

    /// 把锁定时的读数换成可存的值：RSSI ≥ 0（含 macOS 无有效信号时的 127）与距离 ≤ 0 都按「没有读数」处理。
    static func reading(rssi: Double, distance: Double) -> (rssi: Int?, distance: Double?) {
        (rssi < 0 ? Int(rssi.rounded()) : nil, distance > 0 ? distance : nil)
    }
}

/// 锁定记录的本地存储：JSON 文件，位于 `~/Library/Application Support/WatchLock/lock-history.json`。
///
/// 读写都在主线程（记录最多 200 条，几十 KB）。文件损坏 / 读不出时按空记录处理，不影响锁定本身。
final class LockHistoryStore: ObservableObject {
    static let shared = LockHistoryStore(fileURL: LockHistoryStore.defaultFileURL)

    static var defaultFileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base.appendingPathComponent("WatchLock", isDirectory: true)
            .appendingPathComponent("lock-history.json")
    }

    @Published private(set) var records: [LockHistory.Record]

    /// `nil` 表示只在内存里保存（测试用，或取不到应用支持目录）。
    private let fileURL: URL?

    init(fileURL: URL?) {
        self.fileURL = fileURL
        records = Self.load(from: fileURL)
    }

    /// 记一次锁定。
    func record(_ record: LockHistory.Record) {
        records = LockHistory.appending(record, to: records)
        persist()
    }

    /// 把最近一次自动锁定标记为误锁；没有可标记的记录时返回 `false`。
    @discardableResult
    func markLatestAutomaticAsFalse(now: Date = Date(), window: TimeInterval) -> Bool {
        guard let next = LockHistory.markingLatestAutomaticAsFalse(in: records, now: now, window: window) else {
            return false
        }
        records = next
        persist()
        return true
    }

    func clear() {
        records = []
        persist()
    }

    // MARK: - 磁盘

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func load(from url: URL?) -> [LockHistory.Record] {
        guard let url, let data = try? Data(contentsOf: url),
              let decoded = try? makeDecoder().decode([LockHistory.Record].self, from: data) else { return [] }
        // 文件被手动改大时也守住上限。
        return Array(decoded.suffix(LockHistory.capacity))
    }

    private func persist() {
        guard let fileURL, let data = try? Self.makeEncoder().encode(records) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}
