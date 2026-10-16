import Foundation

/// 诊断日志：内存保留 300 条供界面展示，同时**追加写入磁盘**，
/// 这样应用被重新打包/重启后仍可回溯，排查问题也不必依赖用户手动导出。
final class DiagnosticsLog: ObservableObject {
    enum Level: String, CaseIterable, Identifiable {
        case info
        case warning
        case error

        var id: String { rawValue }

        var title: String {
            switch self {
            case .info: return "信息"
            case .warning: return "警告"
            case .error: return "错误"
            }
        }
    }

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let level: Level
        let message: String
    }

    static let shared = DiagnosticsLog()
    private let limit = 300

    /// 落盘位置：`~/Library/Application Support/WatchLock/diagnostics.log`。
    static var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("WatchLock", isDirectory: true)
            .appendingPathComponent("diagnostics.log")
    }

    @Published private(set) var entries: [Entry] = []

    private let fileQueue = DispatchQueue(label: "watchlock.diagnostics.file")
    private let maxFileSize = 512 * 1024

    private init() {}

    func append(_ level: Level, _ message: String) {
        let entry = Entry(date: Date(), level: level, message: message)
        DispatchQueue.main.async {
            self.entries.append(entry)
            if self.entries.count > self.limit {
                self.entries.removeFirst(self.entries.count - self.limit)
            }
        }
        appendToFile(entry)
    }

    /// 追加写文件；超过上限就从头覆盖，避免无限增长。
    private func appendToFile(_ entry: Entry) {
        guard let url = Self.fileURL else { return }
        let formatter = ISO8601DateFormatter()
        let line = "[\(formatter.string(from: entry.date))] [\(entry.level.rawValue.uppercased())] \(entry.message)\n"
        fileQueue.async {
            guard let data = line.data(using: .utf8) else { return }
            let manager = FileManager.default
            if manager.fileExists(atPath: url.path) {
                let size = (try? manager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)??.intValue ?? 0
                guard size <= self.maxFileSize else {
                    try? data.write(to: url)
                    return
                }
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            } else {
                try? manager.createDirectory(at: url.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
                try? data.write(to: url)
            }
        }
    }

    func clear() {
        DispatchQueue.main.async { self.entries.removeAll() }
    }

    func exportText() -> String {
        let formatter = ISO8601DateFormatter()
        return entries.map { entry in
            "[\(formatter.string(from: entry.date))] [\(entry.level.rawValue.uppercased())] \(entry.message)"
        }.joined(separator: "\n")
    }
}
