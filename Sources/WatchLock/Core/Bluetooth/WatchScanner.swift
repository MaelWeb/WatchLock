import Combine
import CoreBluetooth
import Foundation

/// 蓝牙扫描占空策略（FR-12 低耗电）。
///
/// - continuous：常驻扫描，用于正常监听状态；
/// - lowPower：间歇扫描（扫 2 秒、停 3 秒），用于暂停 / 关闭自动锁定时降低耗电。
enum ScanMode: Equatable {
    case continuous
    case lowPower
}

/// 负责持续扫描周边 BLE 设备，挑出可能是 Apple Watch 的候选，并输出 RSSI 样本。
final class WatchScanner: NSObject, ObservableObject, CBCentralManagerDelegate {
    @Published private(set) var isScanning = false
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var candidates: [UUID: DiscoveredWatch] = [:]
    /// 所有被发现的 BLE 设备（含未匹配的），用于「搜不到手表」时的诊断（R-02）。
    @Published private(set) var allDevices: [UUID: DiscoveredWatch] = [:]
    @Published private(set) var lastError: String?
    /// 收到的广播总数，以及其中 RSSI 无效（127）的数量——用于诊断「扫描中却看不到设备」。
    @Published private(set) var discoveryCount = 0

    /// 每次发现（含重复广播）都会回调，携带外设 ID 与 RSSI。
    var onRSSI: ((UUID, Int, Date) -> Void)?

    /// 收到广播但系统未提供有效 RSSI（127）时的回调：设备仍在场，只是测不到强度。
    var onPresence: ((UUID, Date) -> Void)?

    /// 用户已绑定的手表 ID；命中后始终作为候选。
    var boundIdentifier: UUID?

    /// 辅助设备（iPhone / AirPods 等）的外设标识。命中且 RSSI 有效时走 `onAuxiliaryRSSI`，
    /// **不会**进入手表的候选列表，也不会喂给距离状态机。
    var auxiliaryIdentifiers: Set<UUID> = []
    var onAuxiliaryRSSI: ((UUID, Int, Date) -> Void)?

    private var central: CBCentralManager!
    private var shouldScan = false
    private var mode: ScanMode = .continuous
    private var dutyTimer: Timer?

    /// 低耗电模式下的扫描窗口与空闲窗口（秒）。
    private let lowPowerScanWindow: TimeInterval = 2
    private let lowPowerIdleWindow: TimeInterval = 3

    override init() {
        super.init()
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
    }

    func start() {
        shouldScan = true
        applyMode()
    }

    func stop() {
        shouldScan = false
        cancelDutyTimer()
        if central.state == .poweredOn {
            central.stopScan()
        }
        isScanning = false
    }

    /// 切换扫描占空策略；未启动时只记录，等 `start()` 后生效。
    func setMode(_ newMode: ScanMode) {
        guard newMode != mode else { return }
        mode = newMode
        guard shouldScan else { return }
        applyMode()
    }

    private func applyMode() {
        cancelDutyTimer()
        guard shouldScan else { return }
        switch mode {
        case .continuous:
            startScanning()
        case .lowPower:
            beginScanWindow()
        }
    }

    private func startScanning() {
        guard shouldScan, central.state == .poweredOn else { return }
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
    }

    private func beginScanWindow() {
        startScanning()
        scheduleDutyTimer(interval: lowPowerScanWindow) { [weak self] in
            self?.endScanWindow()
        }
    }

    private func endScanWindow() {
        guard shouldScan, mode == .lowPower else { return }
        if central.state == .poweredOn {
            central.stopScan()
        }
        isScanning = false
        scheduleDutyTimer(interval: lowPowerIdleWindow) { [weak self] in
            self?.beginScanWindow()
        }
    }

    private func scheduleDutyTimer(interval: TimeInterval, handler: @escaping () -> Void) {
        cancelDutyTimer()
        let timer = Timer(timeInterval: interval, repeats: false) { _ in handler() }
        RunLoop.main.add(timer, forMode: .common)
        dutyTimer = timer
    }

    private func cancelDutyTimer() {
        dutyTimer?.invalidate()
        dutyTimer = nil
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        switch central.state {
        case .poweredOn:
            lastError = nil
            applyMode()
        case .poweredOff:
            lastError = String(localized: "蓝牙已关闭，请在系统设置中开启蓝牙")
            isScanning = false
        case .unauthorized:
            lastError = String(localized: "没有蓝牙权限，请在「系统设置 → 隐私与安全性 → 蓝牙」中授权")
            isScanning = false
        case .unsupported:
            lastError = String(localized: "当前设备不支持低功耗蓝牙")
            isScanning = false
        case .resetting:
            lastError = String(localized: "蓝牙模块正在重置")
            isScanning = false
        case .unknown:
            lastError = nil
            isScanning = false
        @unknown default:
            lastError = String(localized: "蓝牙状态未知")
            isScanning = false
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        discoveryCount += 1
        let rssi = RSSI.intValue
        // RSSI = 127 是 CoreBluetooth 的「不可用」哨兵值。macOS 部分状态下会对所有广播都上报 127，
        // 此时不能把整个扫描结果丢掉：设备与广播内容照常记录（抓包/诊断用），
        // 只是不喂给距离状态机（会被当成极近信号），也不进候选列表。

        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name
        let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data

        let matched = WatchMatcher.evaluate(
            name: name,
            serviceUUIDs: serviceUUIDs,
            manufacturerData: manufacturerData,
            boundIdentifier: boundIdentifier,
            peripheralIdentifier: peripheral.identifier
        )

        let now = Date()
        var raw = allDevices[peripheral.identifier] ?? DiscoveredWatch(
            id: peripheral.identifier,
            name: name ?? "",
            rssi: RSSI.intValue,
            lastSeen: now,
            matchReasons: matched.reasons
        )
        raw.name = name ?? raw.name
        raw.rssi = RSSI.intValue
        raw.lastSeen = now
        raw.matchReasons = matched.reasons
        raw.serviceUUIDs = Set(serviceUUIDs.map(\.uuidString))
        raw.manufacturerData = manufacturerData
        allDevices[peripheral.identifier] = raw

        if rssi < 0, auxiliaryIdentifiers.contains(peripheral.identifier) {
            onAuxiliaryRSSI?(peripheral.identifier, rssi, now)
        }

        // RSSI 无效时不进候选、不喂距离状态机，但设备已记录（见上方说明），
        // 并且要告诉上层「手表还在广播」，避免被当成信号丢失而锁屏。
        guard rssi < 0 else {
            onPresence?(peripheral.identifier, now)
            return
        }
        guard matched.isStrongCandidate else { return }

        var device = candidates[peripheral.identifier] ?? DiscoveredWatch(
            id: peripheral.identifier,
            name: name ?? "",
            rssi: RSSI.intValue,
            lastSeen: now,
            matchReasons: matched.reasons
        )
        device.name = name ?? device.name
        device.rssi = RSSI.intValue
        device.lastSeen = now
        device.matchReasons = matched.reasons
        candidates[peripheral.identifier] = device

        onRSSI?(peripheral.identifier, RSSI.intValue, now)
    }

    /// 清理长时间未被观察到的设备。
    func prune(olderThan interval: TimeInterval) {
        let deadline = Date().addingTimeInterval(-interval)
        allDevices = allDevices.filter { $0.value.lastSeen >= deadline }
        candidates = candidates.filter { $0.value.lastSeen >= deadline }
    }
}
