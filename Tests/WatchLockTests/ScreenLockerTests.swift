import XCTest
@testable import WatchLock

/// 锁屏命令拼装与 AppleScript 转义（对应需求 §14.1）。
final class ScreenLockerTests: XCTestCase {
    func testPresetMethodsHaveCommands() {
        // 自定义命令由用户填写；系统接口是进程内调用，都没有预置命令。
        for method in LockMethod.allCases where method.usesShellCommand && method != .customCommand {
            XCTAssertNotNil(method.command, "\(method.title) 缺少命令")
            XCTAssertFalse(method.command?.isEmpty ?? true)
        }
    }

    func testOnlySystemLockScreenSkipsShell() {
        XCTAssertFalse(LockMethod.systemLockScreen.usesShellCommand)
        XCTAssertNil(LockMethod.systemLockScreen.command)
        for method in LockMethod.allCases where method != .systemLockScreen {
            XCTAssertTrue(method.usesShellCommand, "\(method.title) 应通过 shell 执行")
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

    // MARK: - 系统私有锁屏接口

    func testSystemLockScreenDoesNotRequireAccessibility() {
        XCTAssertFalse(LockMethod.systemLockScreen.requiresAccessibility)
        // 即便辅助功能未授权，也不应被拦截，且不应触发辅助功能检查（避免弹授权框）。
        var accessibilityChecked = false
        let locker = ScreenLocker(
            method: .systemLockScreen,
            customCommand: "",
            accessibilityCheck: {
                accessibilityChecked = true
                return false
            },
            systemLockCheck: { true }
        )
        XCTAssertNil(locker.permissionIssue())
        XCTAssertFalse(accessibilityChecked)
    }

    func testSystemLockScreenReportsIssueWhenAPIUnavailable() {
        let locker = ScreenLocker(method: .systemLockScreen, customCommand: "", systemLockCheck: { false })
        XCTAssertEqual(locker.permissionIssue(), ScreenLocker.systemAPIGuidance)
    }

    func testSystemLockScreenCommandIsAlwaysValid() {
        let locker = ScreenLocker(method: .systemLockScreen, customCommand: "")
        XCTAssertTrue(locker.isCommandValid)
    }

    func testSystemLockScreenInvokesInjectedLock() {
        var calls = 0
        let locker = ScreenLocker(
            method: .systemLockScreen,
            customCommand: "",
            systemLockCheck: { true },
            systemLock: {
                calls += 1
                return true
            }
        )
        XCTAssertTrue(locker.lock())
        XCTAssertEqual(calls, 1)
    }

    func testSystemLockScreenFailureIsReported() {
        var calls = 0
        let locker = ScreenLocker(
            method: .systemLockScreen,
            customCommand: "",
            systemLockCheck: { true },
            systemLock: {
                calls += 1
                return false
            }
        )
        XCTAssertFalse(locker.lock())
        XCTAssertEqual(calls, 1)
    }

    func testSystemLockScreenSkipsInvocationWhenUnavailable() {
        var calls = 0
        let locker = ScreenLocker(
            method: .systemLockScreen,
            customCommand: "",
            systemLockCheck: { false },
            systemLock: {
                calls += 1
                return true
            }
        )
        // 预检不通过时不应去调用私有接口。
        XCTAssertFalse(locker.lock())
        XCTAssertEqual(calls, 0)
    }

    func testPermissionIssueNotificationBodyMatchesMethod() {
        XCTAssertEqual(
            ScreenLocker(method: .systemLockScreen, customCommand: "").permissionIssueNotificationBody,
            ScreenLocker.systemAPINotificationBody
        )
        XCTAssertEqual(
            ScreenLocker(method: .controlCommandQ, customCommand: "").permissionIssueNotificationBody,
            ScreenLocker.accessibilityNotificationBody
        )
    }

    func testSystemLockScreenSymbolResolutionDoesNotLock() {
        // 只解析符号，不调用；用于确认 dlopen/dlsym 路径本身不会崩溃。
        _ = SystemLockScreen.isAvailable
        _ = SystemLockScreen.resolve()
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
