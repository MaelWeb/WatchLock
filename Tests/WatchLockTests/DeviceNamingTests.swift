import Foundation
import XCTest

@testable import WatchLock

/// 名称 / 图标的优先级：用户自定义 > 快照 > 实时广播 > 型号；图标另有型号与名称推断。
final class DeviceNamingTests: XCTestCase {
    private let id = "1A2B3C4D-0000-0000-0000-000000000001"

    private func resolve(
        live: String = "",
        model: AirPodsModel? = nil,
        snapshot: String? = nil,
        snapshotModel: AirPodsModel? = nil,
        override: DeviceOverride? = nil,
        fallback: DeviceKind = .unknown
    ) -> DeviceLabel {
        DeviceNaming.resolve(
            id: id,
            liveName: live,
            model: model,
            snapshotName: snapshot,
            snapshotModel: snapshotModel,
            override: override,
            fallbackKind: fallback
        )
    }

    func testSnapshotWinsOverLiveName() {
        let label = resolve(live: "", snapshot: "Zero@Apple Watch")
        XCTAssertEqual(label.name, "Zero@Apple Watch")
        XCTAssertTrue(label.hasRealName)

        // 广播里偶尔换了名字，已绑定设备仍显示绑定时的名称。
        XCTAssertEqual(resolve(live: "Other", snapshot: "Zero@Apple Watch").name, "Zero@Apple Watch")
    }

    func testPlaceholderSnapshotIsNotTreatedAsRealName() {
        let label = resolve(live: "Zero's iPhone", snapshot: "1A2B3C4D")
        XCTAssertEqual(label.name, "Zero's iPhone")
    }

    func testNoNameAnywhereShowsModelThenIdentifierSuffix() {
        let unnamed = resolve()
        XCTAssertTrue(unnamed.name.hasSuffix(" · 1A2B3C4D"))
        XCTAssertFalse(unnamed.hasRealName)

        let airpods = resolve(model: .airPodsPro)
        XCTAssertEqual(airpods.name, "AirPods Pro · 1A2B3C4D")
        XCTAssertFalse(airpods.hasRealName)
    }

    func testCustomNameBeatsEverything() {
        let label = resolve(live: "Live", snapshot: "Snap", override: DeviceOverride(name: "我的手表", kind: nil))
        XCTAssertEqual(label.name, "我的手表")
    }

    func testCustomKindBeatsModelAndName() {
        let label = resolve(live: "Zero's iPhone", model: .airPodsPro, override: DeviceOverride(name: nil, kind: .keyboard))
        XCTAssertEqual(label.kind, .keyboard)
    }

    func testModelBeatsNameInference() {
        XCTAssertEqual(resolve(live: "Zero's iPhone", model: .airPodsMax).kind, .airPodsMax)
    }

    func testSnapshotModelUsedWhenLiveFrameHasNone() {
        XCTAssertEqual(resolve(snapshotModel: .airPodsPro).kind, .airPodsPro)
    }

    func testKindInferredFromAnyAvailableName() {
        XCTAssertEqual(resolve(live: "Zero's iPhone").kind, .iPhone)
        // 自定义名认不出时，仍可从快照 / 实时名推断。
        let label = resolve(live: "Zero's iPhone", override: DeviceOverride(name: "老王", kind: nil))
        XCTAssertEqual(label.kind, .iPhone)
    }

    func testFallbackKindOnlyWhenNothingRecognized() {
        XCTAssertEqual(resolve(fallback: .watch).kind, .watch)
        XCTAssertEqual(resolve(live: "Zero's iPhone", fallback: .watch).kind, .iPhone)
        XCTAssertEqual(resolve().kind, .unknown)
    }

    func testSnapshotNamePrefersNameThenModelThenPlaceholder() {
        XCTAssertEqual(DeviceNaming.snapshotName(name: "Watch", model: .airPodsPro, id: id), "Watch")
        XCTAssertEqual(DeviceNaming.snapshotName(name: "", model: .airPodsPro, id: id), "AirPods Pro")
        XCTAssertEqual(DeviceNaming.snapshotName(name: "", model: nil, id: id), "1A2B3C4D")
        XCTAssertTrue(DeviceNaming.isPlaceholder("1a2b3c4d", id: id))
    }

    func testOverrideNormalizationTrimsAndTruncates() {
        XCTAssertNil(DeviceOverride(name: "   ", kind: nil).normalized().name)
        XCTAssertEqual(DeviceOverride(name: "  老王  ", kind: nil).normalized().name, "老王")
        let long = String(repeating: "a", count: 100)
        XCTAssertEqual(DeviceOverride(name: long, kind: nil).normalized().name?.count, DeviceOverride.maxNameLength)
    }
}
