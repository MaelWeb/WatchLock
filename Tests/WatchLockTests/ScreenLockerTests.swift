import XCTest
@testable import WatchLock

/// 锁屏命令拼装与 AppleScript 转义（对应需求 §14.1）。
final class ScreenLockerTests: XCTestCase {
    func testPresetMethodsHaveCommands() {
        for method in LockMethod.allCases where method != .customCommand {
            XCTAssertNotNil(method.command, "\(method.title) 缺少命令")
            XCTAssertFalse(method.command?.isEmpty ?? true)
        }
    }

    func testControlCommandQUsesSystemEvents() {
        let command = LockMethod.controlCommandQ.command ?? ""
        XCTAssertTrue(command.contains("/usr/bin/osascript"))
        XCTAssertTrue(command.contains("System Events"))
        XCTAssertTrue(command.contains("keystroke"))
        XCTAssertTrue(command.contains("command down"))
        XCTAssertTrue(command.contains("control down"))
    }

    func testCGSessionCommand() {
        let command = LockMethod.cgSessionSuspend.command ?? ""
        XCTAssertTrue(command.contains("CGSession"))
        XCTAssertTrue(command.contains("-suspend"))
        // 路径含空格，必须整体加引号
        XCTAssertTrue(command.hasPrefix("\""))
    }

    func testPmsetCommands() {
        XCTAssertEqual(LockMethod.displaySleep.command, "/usr/bin/pmset displaysleepnow")
        XCTAssertEqual(LockMethod.systemSleep.command, "/usr/bin/pmset sleepnow")
    }

    func testCustomCommandResolution() {
        let locker = ScreenLocker(method: .customCommand, customCommand: "~/scripts/lock.sh --fast")
        XCTAssertEqual(locker.resolvedCommand, "~/scripts/lock.sh --fast")
        XCTAssertTrue(locker.isCommandValid)
    }

    func testEmptyCustomCommandIsInvalid() {
        let locker = ScreenLocker(method: .customCommand, customCommand: "   ")
        XCTAssertFalse(locker.isCommandValid)
    }

    // MARK: - 辅助功能权限预检

    func testOnlyControlCommandQRequiresAccessibility() {
        XCTAssertTrue(LockMethod.controlCommandQ.requiresAccessibility)
        for method in LockMethod.allCases where method != .controlCommandQ {
            XCTAssertFalse(method.requiresAccessibility, "\(method.title) 不应要求辅助功能")
        }
    }

    func testPermissionIssueWhenAccessibilityMissing() {
        let locker = ScreenLocker(method: .controlCommandQ, customCommand: "", accessibilityCheck: { false })
        XCTAssertEqual(locker.permissionIssue(), ScreenLocker.accessibilityGuidance)
    }

    func testNoPermissionIssueWhenAccessibilityGranted() {
        let locker = ScreenLocker(method: .controlCommandQ, customCommand: "", accessibilityCheck: { true })
        XCTAssertNil(locker.permissionIssue())
    }

    func testMethodsWithoutAccessibilityNeverReportPermissionIssue() {
        // 即便系统没授权辅助功能，pmset 等方式也不应被拦截。
        let locker = ScreenLocker(method: .displaySleep, customCommand: "", accessibilityCheck: { false })
        XCTAssertNil(locker.permissionIssue())
    }

    func testLockIsBlockedWithoutAccessibilityAndDoesNotRunCommand() {
        var checked = false
        let locker = ScreenLocker(method: .controlCommandQ, customCommand: "", accessibilityCheck: {
            checked = true
            return false
        })
        // 缺权限时直接返回 false，不会真的去执行 osascript。
        XCTAssertFalse(locker.lock())
        XCTAssertTrue(checked)
    }

    func testDetectsAccessibilityDeniedOutput() {
        let real = "36:84: execution error: “System Events”遇到一个错误：“osascript”不允许发送按键。 (1002)"
        XCTAssertTrue(ScreenLocker.isAccessibilityDenied(output: real))
        XCTAssertTrue(ScreenLocker.isAccessibilityDenied(output: "osascript is not allowed to send keystrokes. (1002)"))
        XCTAssertFalse(ScreenLocker.isAccessibilityDenied(output: "execution error: Application isn’t running. (-600)"))
        XCTAssertFalse(ScreenLocker.isAccessibilityDenied(output: ""))
    }

    func testAppleScriptQuoteEscapesSpecialCharacters() {
        XCTAssertEqual(AppleScript.quote("plain"), "\"plain\"")
        XCTAssertEqual(AppleScript.quote(#"pa"ss"#), #""pa\"ss""#)
        XCTAssertEqual(AppleScript.quote(#"back\slash"#), #""back\\slash""#)
        XCTAssertEqual(AppleScript.quote(#"a"\"#), #""a\"\\""#)
    }
}
