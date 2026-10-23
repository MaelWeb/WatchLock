import XCTest
@testable import WatchLock

/// 按位置信任（FR-23）：保守判定，定位不准 / 过期 / 缺失一律「不在场所内」。
final class TrustedPlaceLocationTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 5_000_000)
    // 北京天安门附近，仅作坐标样例。
    private let centerLat = 39.9087
    private let centerLon = 116.3975

    private func place(radius: Double = 200) -> TrustedPlace.Place {
        TrustedPlace.Place(name: "公司", gatewayMAC: nil, ssid: nil, latitude: centerLat, longitude: centerLon, radius: radius)
    }

    /// 在中心点正北方向偏移约 `meters` 米（1 纬度度 ≈ 111.2 km）。
    private func fix(northOffset meters: Double = 0, accuracy: Double = 30, at date: Date? = nil) -> TrustedPlace.LocationFix {
        .init(
            latitude: centerLat + meters / 111_195,
            longitude: centerLon,
            horizontalAccuracy: accuracy,
            timestamp: date ?? t0
        )
    }

    // MARK: - 距离

    func testDistanceMatchesKnownValues() {
        XCTAssertEqual(TrustedPlace.distance(fromLatitude: 0, longitude: 0, toLatitude: 0, longitude: 0), 0, accuracy: 0.001)
        // 1 纬度度 ≈ 111.2 km
        XCTAssertEqual(
            TrustedPlace.distance(fromLatitude: 0, longitude: 0, toLatitude: 1, longitude: 0),
            111_195, accuracy: 100
        )
        XCTAssertEqual(
            TrustedPlace.distance(fromLatitude: centerLat, longitude: centerLon,
                                  toLatitude: fix(northOffset: 150).latitude, longitude: centerLon),
            150, accuracy: 1
        )
    }

    // MARK: - 位置匹配

    func testInsideRadiusMatches() {
        XCTAssertTrue(TrustedPlace.matchesLocation(place(), fix: fix(northOffset: 150), now: t0))
    }

    func testOutsideRadiusDoesNotMatch() {
        XCTAssertFalse(TrustedPlace.matchesLocation(place(), fix: fix(northOffset: 260), now: t0))
    }

    func testAccuracyWorseThanRadiusDoesNotMatchEvenAtCenter() {
        // 定位精度差于半径时，这次定位无法证明人在场所内。
        XCTAssertFalse(TrustedPlace.matchesLocation(place(radius: 100), fix: fix(accuracy: 150), now: t0))
        XCTAssertTrue(TrustedPlace.matchesLocation(place(radius: 100), fix: fix(accuracy: 100), now: t0))
    }

    func testInvalidAccuracyDoesNotMatch() {
        XCTAssertFalse(TrustedPlace.matchesLocation(place(), fix: fix(accuracy: -1), now: t0))
    }

    func testStaleFixDoesNotMatch() {
        let old = fix(at: t0)
        XCTAssertTrue(TrustedPlace.matchesLocation(place(), fix: old, now: t0.addingTimeInterval(TrustedPlace.locationMaxAge)))
        XCTAssertFalse(TrustedPlace.matchesLocation(place(), fix: old, now: t0.addingTimeInterval(TrustedPlace.locationMaxAge + 1)))
    }

    func testMissingFixDoesNotMatch() {
        XCTAssertFalse(TrustedPlace.matchesLocation(place(), fix: nil, now: t0))
    }

    func testNetworkPlaceIsNotAffectedByLocation() {
        let home = TrustedPlace.Place(name: "家", gatewayMAC: "aa:bb:cc:dd:ee:01", ssid: nil)
        let snapshot = TrustedPlace.Snapshot(gatewayMAC: nil, ssid: nil, location: fix())
        XCTAssertNil(TrustedPlace.match(snapshot, in: [home], now: t0))
    }

    func testEitherNetworkOrLocationMatchesPlace() {
        let home = TrustedPlace.Place(name: "家", gatewayMAC: "aa:bb:cc:dd:ee:01", ssid: nil)
        let office = place()
        let places = [home, office]

        // 换了网络（手机热点）但人还在公司：位置命中。
        let onHotspot = TrustedPlace.Snapshot(gatewayMAC: "11:22:33:44:55:66", ssid: nil, location: fix(northOffset: 50))
        XCTAssertEqual(TrustedPlace.match(onHotspot, in: places, now: t0)?.name, "公司")

        // 没有定位但网关命中：网络命中。
        let atHome = TrustedPlace.Snapshot(gatewayMAC: "aa:bb:cc:dd:ee:01", ssid: nil, location: nil)
        XCTAssertEqual(TrustedPlace.match(atHome, in: places, now: t0)?.name, "家")

        // 都不命中。
        let away = TrustedPlace.Snapshot(gatewayMAC: "11:22:33:44:55:66", ssid: nil, location: fix(northOffset: 5_000))
        XCTAssertNil(TrustedPlace.match(away, in: places, now: t0))
    }

    // MARK: - 保存

    func testCanSaveLocationRequiresFreshAccurateFix() {
        XCTAssertEqual(TrustedPlace.canSaveLocation(nil, radius: 200, existing: [], now: t0), .noFix)
        XCTAssertEqual(
            TrustedPlace.canSaveLocation(fix(), radius: 200, existing: [], now: t0.addingTimeInterval(500)),
            .noFix
        )
        XCTAssertEqual(
            TrustedPlace.canSaveLocation(fix(accuracy: 300), radius: 200, existing: [], now: t0),
            .inaccurate(accuracy: 300)
        )
        XCTAssertEqual(TrustedPlace.canSaveLocation(fix(accuracy: 30), radius: 200, existing: [], now: t0), .ok)
    }

    func testCanSaveLocationRejectsInvalidCoordinates() {
        let bad = TrustedPlace.LocationFix(latitude: 120, longitude: 0, horizontalAccuracy: 10, timestamp: t0)
        XCTAssertEqual(TrustedPlace.canSaveLocation(bad, radius: 200, existing: [], now: t0), .noFix)
    }

    func testCanSaveLocationDetectsExistingPlace() {
        XCTAssertEqual(
            TrustedPlace.canSaveLocation(fix(northOffset: 40), radius: 200, existing: [place()], now: t0),
            .alreadySaved(name: "公司")
        )
    }

    func testSavingNetworkIsNotBlockedByLocationPlace() {
        let snapshot = TrustedPlace.Snapshot(gatewayMAC: "aa:bb:cc:dd:ee:01", ssid: nil, location: fix())
        XCTAssertEqual(TrustedPlace.canSave(snapshot, existing: [place()]), .ok)
    }

    func testMakeLocationPlaceUsesNameOrFallback() {
        let named = TrustedPlace.makeLocationPlace(from: fix(), name: " 公司 ", radius: 200, fallbackName: "当前位置")
        XCTAssertEqual(named.name, "公司")
        XCTAssertTrue(named.isLocationPlace)
        XCTAssertNil(named.gatewayMAC)
        XCTAssertEqual(named.radius, 200)

        let unnamed = TrustedPlace.makeLocationPlace(from: fix(), name: "  ", radius: 100, fallbackName: "当前位置")
        XCTAssertEqual(unnamed.name, "当前位置")
    }

    // MARK: - 持久化兼容

    func testPlaceSavedByOlderVersionStillDecodes() throws {
        let legacy = Data(#"[{"id":"00000000-0000-0000-0000-000000000001","name":"家","gatewayMAC":"aa:bb:cc:dd:ee:01","ssid":"Home"}]"#.utf8)
        let places = try JSONDecoder().decode([TrustedPlace.Place].self, from: legacy)
        XCTAssertEqual(places.first?.gatewayMAC, "aa:bb:cc:dd:ee:01")
        XCTAssertFalse(places.first?.isLocationPlace ?? true)
    }

    func testLocationPlaceRoundTrips() throws {
        let data = try JSONEncoder().encode([place(radius: 500)])
        let decoded = try JSONDecoder().decode([TrustedPlace.Place].self, from: data)
        XCTAssertEqual(decoded.first?.radius, 500)
        XCTAssertTrue(decoded.first?.isLocationPlace ?? false)
    }

    // MARK: - 状态机

    func testTrackerEntersByLocationAndLeavesAfterFixGoesStale() {
        var tracker = TrustedPlace.Tracker(leaveDebounce: 8)
        let office = place()
        let inside = TrustedPlace.Snapshot(gatewayMAC: nil, ssid: nil, location: fix(northOffset: 30))
        XCTAssertEqual(tracker.update(snapshot: inside, places: [office], now: t0), .entered(office))

        // 定位一直没更新：超过有效期后按「离开」处理（再走防抖）。
        let stale = t0.addingTimeInterval(TrustedPlace.locationMaxAge + 1)
        XCTAssertEqual(tracker.update(snapshot: inside, places: [office], now: stale), .none)
        XCTAssertEqual(tracker.update(snapshot: inside, places: [office], now: stale.addingTimeInterval(9)), .left)
    }

    @MainActor
    func testMonitorIgnoresLocationWithoutAuthorization() {
        let office = place()
        var authorized = false
        let monitor = TrustedPlaceMonitor(
            leaveDebounce: 8,
            probe: { _ in .init(gatewayMAC: nil, ssid: nil) },
            locationFix: { [self] in fix(northOffset: 10, at: Date()) },
            isLocationAuthorized: { authorized }
        )

        XCTAssertEqual(monitor.update(places: [office], enabled: true), .none)
        XCTAssertNil(monitor.snapshot.location, "没有授权时不能带着旧定位结果")

        authorized = true
        XCTAssertEqual(monitor.update(places: [office], enabled: true), .entered(office))
        XCTAssertEqual(monitor.current?.id, office.id)
    }
}
