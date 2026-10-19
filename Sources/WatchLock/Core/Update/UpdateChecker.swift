import Foundation

/// 「检查更新」（FR-18）。
///
/// 边界（与「零网络请求」承诺的关系，见 ADR-13）：
/// - 只在用户点击「检查更新」时发起**一次** HEAD 请求，不做后台轮询，不带任何本机信息；
/// - 不自动下载、不自动安装：应用未公证，原地替换自身既不安全也会让蓝牙 / 辅助功能授权失效，
///   发现新版本后只打开 GitHub Releases 页面，由用户自行下载。
/// - 请求 `releases/latest` 的 302 跳转目标（`.../releases/tag/vX.Y.Z`）取版本号，
///   不走 api.github.com，因此没有匿名 60 次 / 小时的限流。
enum UpdateChecker {
    static let repository = "MaelWeb/WatchLock"
    static let latestURL = URL(string: "https://github.com/\(repository)/releases/latest")!
    static let releasesURL = URL(string: "https://github.com/\(repository)/releases")!

    /// 帮助手册：随系统语言选英文或中文版本（只是打开浏览器，应用本身不发请求）。
    static func helpURL(preferredLanguages: [String]) -> URL {
        let isChinese = preferredLanguages.first?.lowercased().hasPrefix("zh") ?? false
        let file = isChinese ? "help.md" : "help.en.md"
        return URL(string: "https://github.com/\(repository)/blob/main/docs/\(file)")!
    }

    enum Outcome: Equatable {
        case upToDate(current: String)
        case available(latest: String, current: String, page: URL)
        /// 仓库还没有任何发布（跳转落在 /releases 列表页）。
        case noRelease
        case failed(String)
    }

    // MARK: - 纯逻辑（可单测）

    /// 从跳转后的 URL 取版本号：`.../releases/tag/v1.2.3` → `1.2.3`；其他形态返回 nil。
    static func version(fromRedirected url: URL) -> String? {
        let parts = url.pathComponents
        guard let index = parts.lastIndex(of: "tag"), index + 1 < parts.count else { return nil }
        var tag = parts[index + 1]
        if tag.hasPrefix("v") || tag.hasPrefix("V") { tag.removeFirst() }
        return components(of: tag) == nil ? nil : tag
    }

    /// 数字段比较（忽略预发布后缀）；`remote` 比 `local` 新才返回 true。无法解析一律返回 false，宁可不提示。
    static func isNewer(_ remote: String, than local: String) -> Bool {
        guard var lhs = components(of: remote), var rhs = components(of: local) else { return false }
        let count = max(lhs.count, rhs.count)
        lhs += Array(repeating: 0, count: count - lhs.count)
        rhs += Array(repeating: 0, count: count - rhs.count)
        return lhs.lexicographicallyPrecedes(rhs) == false && lhs != rhs
    }

    static func outcome(finalURL: URL?, current: String) -> Outcome {
        guard let finalURL else { return .failed(String(localized: "没有收到有效响应")) }
        guard let latest = version(fromRedirected: finalURL) else { return .noRelease }
        return isNewer(latest, than: current)
            ? .available(latest: latest, current: current, page: finalURL)
            : .upToDate(current: current)
    }

    private static func components(of version: String) -> [Int]? {
        let core = version.split(separator: "-", maxSplits: 1).first.map(String.init) ?? version
        let numbers = core.split(separator: ".").map { Int($0) }
        guard !numbers.isEmpty, numbers.allSatisfy({ $0 != nil }) else { return nil }
        return numbers.compactMap { $0 }
    }

    // MARK: - 网络（仅用户点击时调用）

    static func check(current: String, session: URLSession = .shared) async -> Outcome {
        var request = URLRequest(url: latestURL, timeoutInterval: 10)
        request.httpMethod = "HEAD"
        request.setValue("WatchLock", forHTTPHeaderField: "User-Agent")
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return .failed(String(localized: "GitHub 返回了异常状态，请稍后再试"))
            }
            return outcome(finalURL: http.url, current: current)
        } catch {
            return .failed(String(localized: "无法连接 GitHub：\(error.localizedDescription)"))
        }
    }
}
