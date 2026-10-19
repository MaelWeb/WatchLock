// 调研探针：记录 LocalAuthentication 的 companion 策略随「手表状态」的变化。
//
// 用途：验证「companion 策略能否当作手表离开 / 佩戴状态的信号」（见 docs/anti-false-lock-research.md §6.3）。
// 只调用 canEvaluatePolicy（不会弹出认证界面、不会锁屏）。
//
// 用法：
//   swiftc -o /tmp/wl_companion_probe Scripts/probe-companion.swift
//   /tmp/wl_companion_probe [总时长秒，默认 1800] [采样间隔秒，默认 1]
//
// 只在状态变化时打印一行（外加每 60 秒一条心跳），每行带本地时间，方便与你的操作时间对照。
import CoreGraphics
import Foundation
import LocalAuthentication

setvbuf(stdout, nil, _IOLBF, 0)

let args = CommandLine.arguments
let total = args.count > 1 ? (Double(args[1]) ?? 1800) : 1800
let interval = args.count > 2 ? (Double(args[2]) ?? 1) : 1

struct Snapshot: Equatable {
    var companion: Bool
    var companionCode: Int?
    var bioOrCompanion: Bool
    var screenLocked: Bool
}

func probe() -> Snapshot {
    let c = LAContext()
    var error: NSError?
    let companion = c.canEvaluatePolicy(.deviceOwnerAuthenticationWithCompanion, error: &error)
    let code = error?.code
    let b = LAContext()
    var bError: NSError?
    let both = b.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometricsOrCompanion, error: &bError)
    let dict = CGSessionCopyCurrentDictionary() as? [String: Any]
    let locked = dict?["CGSSessionScreenIsLocked"] != nil
    return Snapshot(companion: companion, companionCode: code, bioOrCompanion: both, screenLocked: locked)
}

let formatter = DateFormatter()
formatter.dateFormat = "HH:mm:ss"

func idleText() -> String {
    guard let any = CGEventType(rawValue: ~0) else { return "?" }
    return String(format: "%.0fs", CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any))
}

func line(_ tag: String, _ s: Snapshot) {
    let code = s.companionCode.map { "#\($0)" } ?? "-"
    print("\(formatter.string(from: Date())) \(tag) companion=\(s.companion)\(code) bioOrCompanion=\(s.bioOrCompanion) screenLocked=\(s.screenLocked) idle=\(idleText())")
}

let start = Date()
var last = probe()
line("START", last)
var lastBeat = Date()
while Date().timeIntervalSince(start) < total {
    Thread.sleep(forTimeInterval: interval)
    let now = probe()
    if now != last {
        line("CHANGE", now)
        last = now
        lastBeat = Date()
    } else if Date().timeIntervalSince(lastBeat) >= 60 {
        line("beat  ", now)
        lastBeat = Date()
    }
}
line("END   ", last)
