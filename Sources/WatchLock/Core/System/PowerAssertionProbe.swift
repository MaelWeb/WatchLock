import CoreGraphics
import Foundation
import IOKit.pwr_mgt

/// 读取系统电源断言与键鼠空闲时长（会议 / 演示豁免与「解锁后重新布防」的输入）。
///
/// 依据（2026-10-19，macOS 26.6.1，均为本机实测）：
/// - `IOPMCopyAssertionsByProcess` 返回 `[pid: [断言字典]]`；字典含 `AssertType`、`AssertionTrueType`、
///   `AssertLevel`（255 = 开）、`Process Name`、`AssertName`、`AssertPID`。
/// - **沙箱内可用**：用与发布包相同的 entitlements 签名的 `.app` 能读到其他进程的断言（裸命令行程序
///   带沙箱会直接 133 退出，不能用来验证）。
/// - `caffeinate -d` 产生 `PreventUserIdleDisplaySleep`；`-i`、`-u` 不产生；`powerd` 自己常驻持有
///   `InternalPreventDisplaySleep`，类型不同，不会被误判。
/// - 旧版 `NoDisplaySleepAssertion` 的 `AssertType` 原样保留、`AssertionTrueType` 归一为
///   `PreventUserIdleDisplaySleep`，所以判定优先看 `AssertionTrueType`。
/// - `CGEventSource.secondsSinceLastEventType(.combinedSessionState, ...)` 沙箱内可用且随时间递增。
///
/// 未验证：具体会议软件（Zoom / Teams / Keynote / 浏览器会议）是否都会持有该断言——
/// 只验证了接口与 `caffeinate`，没有在真实会议里观察。
enum PowerAssertionProbe {
    /// 失败返回 `nil`（调用方按「查不到 = 没有持有者」处理，宁可照常锁屏也不误豁免）。
    static func copyByProcess() -> [NSNumber: [[String: Any]]]? {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let dictionary = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return nil }
        return dictionary
    }

    /// 距离上一次键盘 / 鼠标 / 触控板输入的秒数；取不到有限值时返回 `nil`。
    static func idleSeconds() -> TimeInterval? {
        guard let anyEvent = CGEventType(rawValue: ~0) else { return nil }
        let value = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyEvent)
        return value.isFinite && value >= 0 ? value : nil
    }
}

/// 「阻止显示器睡眠」的持有者，用于判断用户是否正处于会议 / 演示 / 视频等场景。
struct DisplaySleepHolder: Equatable {
    let pid: Int32
    let processName: String
    let assertionName: String
}

enum MeetingExemption {
    static let displaySleepType = "PreventUserIdleDisplaySleep"

    /// 不视为「会议」的进程：`caffeinate` 是用户主动保持唤醒的工具（长时间构建等），
    /// 若计入会让锁屏一直被暂缓到上限。
    static let ignoredProcessNames: Set<String> = ["caffeinate", "powerd", "WatchLock"]

    /// 纯函数：从原始断言表筛出「阻止用户空闲时显示器睡眠」的持有者。
    static func holders(
        from raw: [NSNumber: [[String: Any]]],
        ownPID: Int32 = getpid(),
        ignoredProcessNames: Set<String> = MeetingExemption.ignoredProcessNames
    ) -> [DisplaySleepHolder] {
        var result: [DisplaySleepHolder] = []
        for (pidKey, assertions) in raw {
            let pid = pidKey.int32Value
            guard pid != ownPID else { continue }
            for assertion in assertions {
                let type = (assertion["AssertionTrueType"] as? String) ?? (assertion["AssertType"] as? String)
                guard type == displaySleepType else { continue }
                if let level = (assertion["AssertLevel"] as? NSNumber)?.intValue, level == 0 { continue }
                let name = (assertion["Process Name"] as? String) ?? "pid \(pid)"
                guard !ignoredProcessNames.contains(name) else { continue }
                result.append(DisplaySleepHolder(
                    pid: pid,
                    processName: name,
                    assertionName: (assertion["AssertName"] as? String) ?? ""
                ))
            }
        }
        return result.sorted { ($0.processName, $0.pid) < ($1.processName, $1.pid) }
    }

    static func currentHolders() -> [DisplaySleepHolder] {
        guard let raw = PowerAssertionProbe.copyByProcess() else { return [] }
        return holders(from: raw)
    }

    enum Decision: Equatable {
        case lockNow
        /// 暂缓（会议 / 演示进行中）。
        case deferLock
        /// 已暂缓满上限，不再等待。
        case lockCapped
    }

    /// 纯函数：是否应暂缓本次自动锁定。
    static func decide(
        enabled: Bool,
        holders: [DisplaySleepHolder],
        deferredSince: Date?,
        now: Date,
        maxDeferral: TimeInterval
    ) -> Decision {
        guard enabled, !holders.isEmpty else { return .lockNow }
        if let deferredSince, now.timeIntervalSince(deferredSince) >= maxDeferral { return .lockCapped }
        return .deferLock
    }
}
