import XCTest
@testable import WatchLock

@MainActor
final class TrustedPlaceMonitorTests: XCTestCase {
    private let home = TrustedPlace.Place(name: "家", gatewayMAC: "aa:bb:cc:dd:ee:01", ssid: nil)
    private let t0 = Date(timeIntervalSince1970: 2_000)
    private var current = TrustedPlace.Snapshot(gatewayMAC: nil, ssid: nil)

    private func makeMonitor(debounce: TimeInterval = 8) -> TrustedPlaceMonitor {
        TrustedPlaceMonitor(leaveDebounce: debounce, probe: { [unowned self] _ in self.current })
    }

    func testEntersAndExposesCurrentPlace() {
        let monitor = makeMonitor()
        current = .init(gatewayMAC: home.gatewayMAC, ssid: nil)
        XCTAssertEqual(monitor.update(places: [home], enabled: true, now: t0), .entered(home))
        XCTAssertEqual(monitor.current?.id, home.id)
        XCTAssertEqual(monitor.snapshot.gatewayMAC, home.gatewayMAC)
    }

    func testDisabledNeverEntersEvenOnMatchingNetwork() {
        let monitor = makeMonitor()
        current = .init(gatewayMAC: home.gatewayMAC, ssid: nil)
        XCTAssertEqual(monitor.update(places: [home], enabled: false, now: t0), .none)
        XCTAssertNil(monitor.current)
    }

    func testDisablingWhileInsideClearsSilently() {
        let monitor = makeMonitor()
        current = .init(gatewayMAC: home.gatewayMAC, ssid: nil)
        _ = monitor.update(places: [home], enabled: true, now: t0)
        // 关闭功能是用户主动操作：静默清空，由调用方根据 current 变化收尾，不走「离开」事件。
        XCTAssertEqual(monitor.update(places: [home], enabled: false, now: t0.addingTimeInterval(1)), .none)
        XCTAssertNil(monitor.current)
    }

    func testDeletingCurrentPlaceClearsImmediately() {
        let monitor = makeMonitor()
        current = .init(gatewayMAC: home.gatewayMAC, ssid: nil)
        _ = monitor.update(places: [home], enabled: true, now: t0)
        XCTAssertEqual(monitor.update(places: [], enabled: true, now: t0.addingTimeInterval(1)), .none)
        XCTAssertNil(monitor.current, "场所被删除后不能再按它暂停，哪怕还连着同一个网络")
    }

    func testLeavingUsesDebounce() {
        let monitor = makeMonitor(debounce: 8)
        current = .init(gatewayMAC: home.gatewayMAC, ssid: nil)
        _ = monitor.update(places: [home], enabled: true, now: t0)
        current = .init(gatewayMAC: nil, ssid: nil)
        XCTAssertEqual(monitor.update(places: [home], enabled: true, now: t0.addingTimeInterval(1)), .none)
        XCTAssertNotNil(monitor.current)
        XCTAssertEqual(monitor.update(places: [home], enabled: true, now: t0.addingTimeInterval(10)), .left)
        XCTAssertNil(monitor.current)
    }

    func testResetClearsCurrent() {
        let monitor = makeMonitor()
        current = .init(gatewayMAC: home.gatewayMAC, ssid: nil)
        _ = monitor.update(places: [home], enabled: true, now: t0)
        monitor.reset()
        XCTAssertNil(monitor.current)
    }
}
