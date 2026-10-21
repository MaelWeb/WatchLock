import CoreLocation
import XCTest
@testable import WatchLock

final class TrustedPlaceMACTests: XCTestCase {
    func testNormalizesArpStyleMAC() {
        XCTAssertEqual(TrustedPlace.normalizeMAC("0:0:5e:0:1:25"), "00:00:5e:00:01:25")
    }

    func testNormalizesCaseAndDashes() {
        XCTAssertEqual(TrustedPlace.normalizeMAC("AA-BB-CC-DD-EE-0F"), "aa:bb:cc:dd:ee:0f")
    }

    func testRejectsMalformed() {
        XCTAssertNil(TrustedPlace.normalizeMAC(nil))
        XCTAssertNil(TrustedPlace.normalizeMAC(""))
        XCTAssertNil(TrustedPlace.normalizeMAC("aa:bb:cc:dd:ee"))
        XCTAssertNil(TrustedPlace.normalizeMAC("aa:bb:cc:dd:ee:ff:00"))
        XCTAssertNil(TrustedPlace.normalizeMAC("aa:bb:cc:dd:ee:zz"))
        XCTAssertNil(TrustedPlace.normalizeMAC("aaa:bb:cc:dd:ee:ff"))
    }

    func testRejectsAllZeroAndBroadcast() {
        XCTAssertNil(TrustedPlace.normalizeMAC("00:00:00:00:00:00"))
        XCTAssertNil(TrustedPlace.normalizeMAC("ff:ff:ff:ff:ff:ff"))
    }
}

final class TrustedPlaceMatchTests: XCTestCase {
    private let home = TrustedPlace.Place(name: "家", gatewayMAC: "aa:bb:cc:dd:ee:01", ssid: "Home-5G")
    private let office = TrustedPlace.Place(name: "公司", gatewayMAC: "aa:bb:cc:dd:ee:02", ssid: nil)

    func testMatchesByGatewayMACWithoutSSID() {
        let snapshot = TrustedPlace.Snapshot(gatewayMAC: "aa:bb:cc:dd:ee:01", ssid: nil)
        XCTAssertEqual(TrustedPlace.match(snapshot, in: [home, office])?.id, home.id)
    }

    func testMatchNormalizesBothSides() {
        let place = TrustedPlace.Place(name: "x", gatewayMAC: "AA:BB:CC:DD:EE:01", ssid: nil)
        let snapshot = TrustedPlace.Snapshot(gatewayMAC: "aa:bb:cc:dd:ee:1", ssid: nil)
        XCTAssertEqual(TrustedPlace.match(snapshot, in: [place])?.id, place.id)
    }

    func testDifferentGatewayDoesNotMatch() {
        let snapshot = TrustedPlace.Snapshot(gatewayMAC: "aa:bb:cc:dd:ee:99", ssid: "Home-5G")
        XCTAssertNil(TrustedPlace.match(snapshot, in: [home, office]))
    }

    func testOfflineDoesNotMatch() {
        XCTAssertNil(TrustedPlace.match(.init(gatewayMAC: nil, ssid: nil), in: [home]))
    }

    func testSSIDMismatchVetoesWhenBothKnown() {
        let snapshot = TrustedPlace.Snapshot(gatewayMAC: "aa:bb:cc:dd:ee:01", ssid: "Cafe")
        XCTAssertNil(TrustedPlace.match(snapshot, in: [home]))
    }

    func testMissingCurrentSSIDDoesNotVeto() {
        // 读不到 SSID（未授权）不能当成不匹配，否则没授权时整个功能都废了。
        let snapshot = TrustedPlace.Snapshot(gatewayMAC: "aa:bb:cc:dd:ee:01", ssid: nil)
        XCTAssertNotNil(TrustedPlace.match(snapshot, in: [home]))
        let empty = TrustedPlace.Snapshot(gatewayMAC: "aa:bb:cc:dd:ee:01", ssid: "")
        XCTAssertNotNil(TrustedPlace.match(empty, in: [home]))
    }

    func testSavedPlaceWithoutSSIDAcceptsAnySSID() {
        let snapshot = TrustedPlace.Snapshot(gatewayMAC: "aa:bb:cc:dd:ee:02", ssid: "Whatever")
        XCTAssertEqual(TrustedPlace.match(snapshot, in: [office])?.id, office.id)
    }

    func testCanSave() {
        XCTAssertEqual(TrustedPlace.canSave(.init(gatewayMAC: nil, ssid: nil), existing: []), .offline)
        XCTAssertEqual(TrustedPlace.canSave(.init(gatewayMAC: "aa:bb:cc:dd:ee:01", ssid: nil), existing: [home]),
                       .alreadySaved(name: "家"))
        XCTAssertEqual(TrustedPlace.canSave(.init(gatewayMAC: "aa:bb:cc:dd:ee:77", ssid: nil), existing: [home]), .ok)
    }

    func testMakePlaceNaming() {
        let withSSID = TrustedPlace.makePlace(from: .init(gatewayMAC: "AA:BB:CC:DD:EE:01", ssid: "Home-5G"), fallbackName: "当前网络")
        XCTAssertEqual(withSSID?.name, "Home-5G")
        XCTAssertEqual(withSSID?.gatewayMAC, "aa:bb:cc:dd:ee:01")

        let withoutSSID = TrustedPlace.makePlace(from: .init(gatewayMAC: "aa:bb:cc:dd:ee:01", ssid: nil), fallbackName: "当前网络")
        XCTAssertEqual(withoutSSID?.name, "当前网络")

        let custom = TrustedPlace.makePlace(from: .init(gatewayMAC: "aa:bb:cc:dd:ee:01", ssid: "Home-5G"), name: "  书房  ", fallbackName: "当前网络")
        XCTAssertEqual(custom?.name, "书房")

        XCTAssertNil(TrustedPlace.makePlace(from: .init(gatewayMAC: nil, ssid: nil), fallbackName: "x"))
    }

    func testPlaceCodableRoundTrip() throws {
        let data = try JSONEncoder().encode([home, office])
        let decoded = try JSONDecoder().decode([TrustedPlace.Place].self, from: data)
        XCTAssertEqual(decoded, [home, office])
    }
}

final class TrustedPlaceTrackerTests: XCTestCase {
    private let home = TrustedPlace.Place(name: "家", gatewayMAC: "aa:bb:cc:dd:ee:01", ssid: nil)
    private let office = TrustedPlace.Place(name: "公司", gatewayMAC: "aa:bb:cc:dd:ee:02", ssid: nil)
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private var atHome: TrustedPlace.Snapshot { .init(gatewayMAC: home.gatewayMAC, ssid: nil) }
    private var atOffice: TrustedPlace.Snapshot { .init(gatewayMAC: office.gatewayMAC, ssid: nil) }
    private var elsewhere: TrustedPlace.Snapshot { .init(gatewayMAC: "11:22:33:44:55:66", ssid: nil) }
    private var offline: TrustedPlace.Snapshot { .init(gatewayMAC: nil, ssid: nil) }

    func testEntersImmediately() {
        var tracker = TrustedPlace.Tracker()
        XCTAssertEqual(tracker.update(snapshot: atHome, places: [home], now: t0), .entered(home))
        XCTAssertTrue(tracker.isInTrustedPlace)
    }

    func testNoPlacesNeverEnters() {
        var tracker = TrustedPlace.Tracker()
        XCTAssertEqual(tracker.update(snapshot: atHome, places: [], now: t0), .none)
        XCTAssertFalse(tracker.isInTrustedPlace)
    }

    func testStaysInsideWithoutRepeatedEvents() {
        var tracker = TrustedPlace.Tracker()
        _ = tracker.update(snapshot: atHome, places: [home], now: t0)
        XCTAssertEqual(tracker.update(snapshot: atHome, places: [home], now: t0.addingTimeInterval(2)), .none)
        XCTAssertTrue(tracker.isInTrustedPlace)
    }

    func testBriefOutageDoesNotLeave() {
        var tracker = TrustedPlace.Tracker(leaveDebounce: 8)
        _ = tracker.update(snapshot: atHome, places: [home], now: t0)
        XCTAssertEqual(tracker.update(snapshot: offline, places: [home], now: t0.addingTimeInterval(2)), .none)
        XCTAssertEqual(tracker.update(snapshot: offline, places: [home], now: t0.addingTimeInterval(6)), .none)
        XCTAssertTrue(tracker.isInTrustedPlace)
    }

    func testRecoveryDuringDebounceCancelsLeave() {
        var tracker = TrustedPlace.Tracker(leaveDebounce: 8)
        _ = tracker.update(snapshot: atHome, places: [home], now: t0)
        _ = tracker.update(snapshot: offline, places: [home], now: t0.addingTimeInterval(2))
        _ = tracker.update(snapshot: atHome, places: [home], now: t0.addingTimeInterval(5))
        // 恢复后重新计时：再断 7 秒仍不算离开（从 t0+6 起算）。
        _ = tracker.update(snapshot: offline, places: [home], now: t0.addingTimeInterval(6))
        XCTAssertEqual(tracker.update(snapshot: offline, places: [home], now: t0.addingTimeInterval(13)), .none)
        XCTAssertTrue(tracker.isInTrustedPlace)
    }

    func testLeavesAfterDebounce() {
        var tracker = TrustedPlace.Tracker(leaveDebounce: 8)
        _ = tracker.update(snapshot: atHome, places: [home], now: t0)
        _ = tracker.update(snapshot: elsewhere, places: [home], now: t0.addingTimeInterval(2))
        XCTAssertEqual(tracker.update(snapshot: elsewhere, places: [home], now: t0.addingTimeInterval(10)), .left)
        XCTAssertFalse(tracker.isInTrustedPlace)
        // 已经离开后不再重复发事件。
        XCTAssertEqual(tracker.update(snapshot: elsewhere, places: [home], now: t0.addingTimeInterval(12)), .none)
    }

    func testReentersAfterLeaving() {
        var tracker = TrustedPlace.Tracker(leaveDebounce: 1)
        _ = tracker.update(snapshot: atHome, places: [home], now: t0)
        _ = tracker.update(snapshot: elsewhere, places: [home], now: t0.addingTimeInterval(1))
        _ = tracker.update(snapshot: elsewhere, places: [home], now: t0.addingTimeInterval(3))
        XCTAssertEqual(tracker.update(snapshot: atHome, places: [home], now: t0.addingTimeInterval(4)), .entered(home))
    }

    func testSwitchingDirectlyBetweenPlacesStaysInside() {
        var tracker = TrustedPlace.Tracker()
        _ = tracker.update(snapshot: atHome, places: [home, office], now: t0)
        XCTAssertEqual(tracker.update(snapshot: atOffice, places: [home, office], now: t0.addingTimeInterval(1)), .none)
        XCTAssertEqual(tracker.currentPlaceID, office.id)
        XCTAssertTrue(tracker.isInTrustedPlace)
    }

    func testRemovingCurrentPlaceLeavesAfterDebounce() {
        var tracker = TrustedPlace.Tracker(leaveDebounce: 8)
        _ = tracker.update(snapshot: atHome, places: [home], now: t0)
        // 用户删掉了场所：快照不变，但列表里没有了 → 按「不再匹配」处理。
        _ = tracker.update(snapshot: atHome, places: [], now: t0.addingTimeInterval(1))
        XCTAssertEqual(tracker.update(snapshot: atHome, places: [], now: t0.addingTimeInterval(10)), .left)
    }

    func testResetIsImmediate() {
        var tracker = TrustedPlace.Tracker()
        _ = tracker.update(snapshot: atHome, places: [home], now: t0)
        XCTAssertEqual(tracker.reset(), .left)
        XCTAssertFalse(tracker.isInTrustedPlace)
        XCTAssertEqual(tracker.reset(), .none)
    }
}

final class NetworkProbeARPTests: XCTestCase {
    /// 构造一条与内核返回格式一致的路由消息：`rt_msghdr` + `sockaddr_in` + `sockaddr_dl`。
    private func message(ip: [UInt8], mac: [UInt8], interfaceName: String = "", dlLength: Int? = nil) -> [UInt8] {
        let header = MemoryLayout<rt_msghdr>.size
        var sin = [UInt8](repeating: 0, count: 16)
        sin[0] = 16
        sin[1] = UInt8(AF_INET)
        sin[4 ..< 8] = ip[0 ..< 4]

        let name = Array(interfaceName.utf8)
        var dl: [UInt8] = [0, UInt8(AF_LINK), 1, 0, 6, UInt8(name.count), UInt8(mac.count), 0]
        dl += name
        dl += mac
        while dl.count % 4 != 0 { dl.append(0) }
        dl[0] = UInt8(dlLength ?? dl.count)

        var body = [UInt8](repeating: 0, count: header)
        body += sin
        body += dl
        let total = UInt16(body.count)
        body[0] = UInt8(total & 0xff)
        body[1] = UInt8(total >> 8)
        return body
    }

    func testParsesSingleEntry() {
        let bytes = message(ip: [192, 168, 1, 1], mac: [0x00, 0x00, 0x5e, 0x00, 0x01, 0x25])
        XCTAssertEqual(NetworkProbe.parseARP(bytes, length: bytes.count),
                       [.init(ip: "192.168.1.1", mac: "00:00:5e:00:01:25")])
    }

    func testParsesMultipleEntries() {
        let bytes = message(ip: [10, 0, 0, 1], mac: [1, 2, 3, 4, 5, 6])
            + message(ip: [10, 0, 0, 7], mac: [0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff], interfaceName: "en0")
        XCTAssertEqual(NetworkProbe.parseARP(bytes, length: bytes.count), [
            .init(ip: "10.0.0.1", mac: "01:02:03:04:05:06"),
            .init(ip: "10.0.0.7", mac: "aa:bb:cc:dd:ee:ff")
        ])
    }

    func testSkipsIncompleteLinkAddress() {
        // 链路地址长度为 0（ARP 还没解析出来）的条目应该被忽略，而不是返回空 MAC。
        var bytes = message(ip: [192, 168, 1, 9], mac: [])
        let ok = message(ip: [192, 168, 1, 1], mac: [9, 8, 7, 6, 5, 4])
        bytes += ok
        XCTAssertEqual(NetworkProbe.parseARP(bytes, length: bytes.count),
                       [.init(ip: "192.168.1.1", mac: "09:08:07:06:05:04")])
    }

    func testTruncatedBufferDoesNotCrash() {
        let bytes = message(ip: [192, 168, 1, 1], mac: [1, 2, 3, 4, 5, 6])
        for cut in 0 ..< bytes.count {
            _ = NetworkProbe.parseARP(Array(bytes[0 ..< cut]), length: cut)
        }
        XCTAssertEqual(NetworkProbe.parseARP(Array(bytes.dropLast()), length: bytes.count - 1), [])
    }

    func testRejectsBogusMessageLength() {
        var bytes = message(ip: [192, 168, 1, 1], mac: [1, 2, 3, 4, 5, 6])
        bytes[0] = 0xff
        bytes[1] = 0xff
        XCTAssertEqual(NetworkProbe.parseARP(bytes, length: bytes.count), [])
        bytes[0] = 1
        bytes[1] = 0
        XCTAssertEqual(NetworkProbe.parseARP(bytes, length: bytes.count), [])
    }

    func testIgnoresNonIPv4Destination() {
        var bytes = message(ip: [192, 168, 1, 1], mac: [1, 2, 3, 4, 5, 6])
        bytes[MemoryLayout<rt_msghdr>.size + 1] = UInt8(AF_INET6)
        XCTAssertEqual(NetworkProbe.parseARP(bytes, length: bytes.count), [])
    }
}

final class WiFiNameAccessStateTests: XCTestCase {
    func testMapsAuthorizationStatus() {
        XCTAssertEqual(WiFiNameAccess.state(from: .notDetermined, servicesEnabled: true), .notDetermined)
        XCTAssertEqual(WiFiNameAccess.state(from: .denied, servicesEnabled: true), .denied)
        XCTAssertEqual(WiFiNameAccess.state(from: .restricted, servicesEnabled: true), .denied)
        XCTAssertEqual(WiFiNameAccess.state(from: .authorizedAlways, servicesEnabled: true), .authorized)
    }

    func testServicesDisabledWinsOverStatus() {
        XCTAssertEqual(WiFiNameAccess.state(from: .authorizedAlways, servicesEnabled: false), .servicesDisabled)
    }
}
