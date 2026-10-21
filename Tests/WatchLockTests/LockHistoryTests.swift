import XCTest
@testable import WatchLock

/// 锁定记录（FR-21）：追加 / 截断、误锁标记、CSV 导出、本地存储。
final class LockHistoryTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func record(
        _ offset: TimeInterval = 0,
        kind: LockHistory.Record.Kind = .automatic,
        reason: String = "手表离开设定范围",
        rssi: Int? = -78,
        distance: Double? = 4.2,
        markedFalse: Bool = false
    ) -> LockHistory.Record {
        .init(
            date: base.addingTimeInterval(offset),
            kind: kind,
            reason: reason,
            rssi: rssi,
            distance: distance,
            markedFalse: markedFalse
        )
    }

    // MARK: - 追加与截断

    func testAppendingKeepsOrder() {
        let first = record(0), second = record(10)
        let result = LockHistory.appending(second, to: [first])
        XCTAssertEqual(result.map(\.id), [first.id, second.id])
    }

    func testAppendingDropsOldestBeyondCapacity() {
        let records = (0 ..< 5).map { record(TimeInterval($0)) }
        let newest = record(100)
        let result = LockHistory.appending(newest, to: records, capacity: 5)
        XCTAssertEqual(result.count, 5)
        XCTAssertEqual(result.last?.id, newest.id)
        XCTAssertFalse(result.contains { $0.id == records[0].id }, "最旧的一条应被丢弃")
        XCTAssertEqual(result.first?.id, records[1].id)
    }

    // MARK: - 误锁标记

    func testMarkingTargetsLatestAutomaticOnly() {
        let oldAuto = record(0)
        let latestAuto = record(100)
        let manualAfter = record(200, kind: .manual)
        let result = LockHistory.markingLatestAutomaticAsFalse(
            in: [oldAuto, latestAuto, manualAfter],
            now: base.addingTimeInterval(300),
            window: 600
        )
        XCTAssertEqual(result?.map(\.markedFalse), [false, true, false], "只标记最近一次自动锁定，手动锁定不受影响")
    }

    func testMarkingSkipsRearmAndManual() {
        let result = LockHistory.markingLatestAutomaticAsFalse(
            in: [record(0, kind: .manual), record(10, kind: .rearm)],
            now: base.addingTimeInterval(20),
            window: 600
        )
        XCTAssertNil(result, "手动 / 重新布防的锁定不是距离误判，不能被标记为误锁")
    }

    func testMarkingRejectsOutsideWindow() {
        let result = LockHistory.markingLatestAutomaticAsFalse(
            in: [record(0)],
            now: base.addingTimeInterval(601),
            window: 600
        )
        XCTAssertNil(result)
    }

    func testMarkingAtWindowBoundaryStillAllowed() {
        let result = LockHistory.markingLatestAutomaticAsFalse(
            in: [record(0)],
            now: base.addingTimeInterval(600),
            window: 600
        )
        XCTAssertEqual(result?.first?.markedFalse, true)
    }

    func testMarkingTwiceIsRejected() {
        let result = LockHistory.markingLatestAutomaticAsFalse(
            in: [record(0, markedFalse: true)],
            now: base.addingTimeInterval(10),
            window: 600
        )
        XCTAssertNil(result, "同一次锁定只能反馈一次，避免重复计入误锁率")
    }

    func testMarkingEmptyHistory() {
        XCTAssertNil(LockHistory.markingLatestAutomaticAsFalse(in: [], now: base, window: 600))
    }

    // MARK: - 读数换算

    func testReadingTreatsInvalidValuesAsMissing() {
        XCTAssertNil(LockHistory.reading(rssi: 0, distance: 0).rssi, "初始值 0 表示还没有读数")
        XCTAssertNil(LockHistory.reading(rssi: 127, distance: 1).rssi, "127 是 macOS 的无效信号强度")
        XCTAssertNil(LockHistory.reading(rssi: -60, distance: 0).distance)
        XCTAssertNil(LockHistory.reading(rssi: -60, distance: -1).distance)

        let valid = LockHistory.reading(rssi: -77.6, distance: 3.25)
        XCTAssertEqual(valid.rssi, -78)
        XCTAssertEqual(valid.distance, 3.25)
    }

    // MARK: - CSV

    private func utc() -> TimeZone { TimeZone(secondsFromGMT: 0)! }

    func testCSVHeaderAndRow() {
        let text = LockHistory.csv([record(0)], timeZone: utc())
        let lines = text.components(separatedBy: "\r\n")
        XCTAssertEqual(lines[0], "time,kind,reason,rssi_dbm,distance_m,marked_false")
        XCTAssertEqual(lines[1], "2027-01-15T08:00:00Z,automatic,手表离开设定范围,-78,4.2,false")
        XCTAssertEqual(lines[2], "", "以换行结尾")
    }

    func testCSVEmptyValuesAndMarkedFalse() {
        let text = LockHistory.csv(
            [record(0, kind: .manual, reason: "手动锁定", rssi: nil, distance: nil, markedFalse: true)],
            timeZone: utc()
        )
        XCTAssertTrue(text.contains(",manual,手动锁定,,,true\r\n"), text)
    }

    func testCSVEscapesCommasQuotesAndNewlines() {
        let text = LockHistory.csv([record(0, reason: "a,b \"c\"\nd")], timeZone: utc())
        XCTAssertTrue(text.contains("\"a,b \"\"c\"\"\nd\""), text)
    }

    func testCSVOfNothingIsHeaderOnly() {
        XCTAssertEqual(LockHistory.csv([], timeZone: utc()), "time,kind,reason,rssi_dbm,distance_m,marked_false\r\n")
    }

    func testCSVUsesGivenTimeZoneOffset() {
        let tokyo = TimeZone(secondsFromGMT: 9 * 3600)!
        let text = LockHistory.csv([record(0)], timeZone: tokyo)
        XCTAssertTrue(text.contains("2027-01-15T17:00:00+09:00"), text)
    }
}

/// 锁定记录存储：读写磁盘用临时目录，不碰真实的应用支持目录。
final class LockHistoryStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("watchlock-history-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var fileURL: URL { directory.appendingPathComponent("lock-history.json") }

    private func record(_ offset: TimeInterval = 0, kind: LockHistory.Record.Kind = .automatic) -> LockHistory.Record {
        .init(
            date: Date(timeIntervalSince1970: 1_800_000_000 + offset),
            kind: kind,
            reason: "手表离开设定范围",
            rssi: -75,
            distance: 3.5
        )
    }

    func testRecordsSurviveReload() {
        let store = LockHistoryStore(fileURL: fileURL)
        let saved = record()
        store.record(saved)

        let reloaded = LockHistoryStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.records, [saved], "目录不存在时也应能创建并写入，重启后记录仍在")
    }

    func testMarkedFalsePersists() {
        let store = LockHistoryStore(fileURL: fileURL)
        store.record(record(0))
        XCTAssertTrue(store.markLatestAutomaticAsFalse(now: Date(timeIntervalSince1970: 1_800_000_060), window: 600))
        XCTAssertEqual(LockHistoryStore(fileURL: fileURL).records.first?.markedFalse, true)
    }

    func testMarkReturnsFalseWhenNothingToMark() {
        let store = LockHistoryStore(fileURL: fileURL)
        XCTAssertFalse(store.markLatestAutomaticAsFalse(window: 600))
        store.record(record(0, kind: .manual))
        XCTAssertFalse(store.markLatestAutomaticAsFalse(now: Date(timeIntervalSince1970: 1_800_000_060), window: 600))
    }

    func testClearEmptiesMemoryAndDisk() {
        let store = LockHistoryStore(fileURL: fileURL)
        store.record(record())
        store.clear()
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertTrue(LockHistoryStore(fileURL: fileURL).records.isEmpty)
    }

    func testCorruptedFileIsTreatedAsEmpty() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fileURL)
        let store = LockHistoryStore(fileURL: fileURL)
        XCTAssertTrue(store.records.isEmpty, "文件损坏不应影响启动")

        // 损坏后仍可继续记录，并覆盖掉坏文件。
        store.record(record())
        XCTAssertEqual(LockHistoryStore(fileURL: fileURL).records.count, 1)
    }

    func testOversizedFileIsTrimmedOnLoad() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let many = (0 ..< LockHistory.capacity + 30).map { record(TimeInterval($0)) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(many).write(to: fileURL)

        let store = LockHistoryStore(fileURL: fileURL)
        XCTAssertEqual(store.records.count, LockHistory.capacity)
        XCTAssertEqual(store.records.last?.id, many.last?.id, "保留的是最新的记录")
    }

    func testInMemoryStoreWorksWithoutFile() {
        let store = LockHistoryStore(fileURL: nil)
        store.record(record())
        XCTAssertEqual(store.records.count, 1)
    }
}
