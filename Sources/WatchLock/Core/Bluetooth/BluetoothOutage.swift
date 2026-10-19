import CoreBluetooth
import Foundation

/// 蓝牙「不可用」期间的处理规则（纯函数，便于测试）。
///
/// 背景：蓝牙被关闭 / 重置 / 权限缺失时扫描不再产生样本，状态机约 20 秒后会按「信号丢失」锁屏，
/// 而界面给出的原因是「超过设定时间未收到手表信号」——用户并没有走开，也不知道真实原因（FR-09 声明了
/// 蓝牙异常要通知，但此前没有任何地方发送）。
///
/// 这里的取舍：**蓝牙不可用不等于手表离开**，所以期间暂停丢失结算、发通知说明原因；
/// 恢复后重置状态机并给一段宽限期，避免恢复瞬间用陈旧状态误判。
enum BluetoothOutage {
    enum Transition: Equatable {
        case none
        case began
        case ended
    }

    /// `.unknown` 是系统初始化中的占位状态，既不算故障也不算恢复，保持当前判定不变。
    static func isUnavailable(_ state: CBManagerState) -> Bool {
        switch state {
        case .poweredOff, .unauthorized, .unsupported, .resetting: return true
        case .poweredOn, .unknown: return false
        @unknown default: return false
        }
    }

    static func transition(wasUnavailable: Bool, state: CBManagerState) -> Transition {
        if state == .unknown { return .none }
        let unavailable = isUnavailable(state)
        switch (wasUnavailable, unavailable) {
        case (false, true): return .began
        case (true, false): return .ended
        default: return .none
        }
    }

    /// 通知正文：说清楚发生了什么、对锁屏有什么影响。
    static func notificationBody(for state: CBManagerState) -> String {
        let cause: String
        switch state {
        case .poweredOff: cause = "蓝牙已关闭"
        case .unauthorized: cause = "WatchLock 没有蓝牙权限"
        case .unsupported: cause = "当前设备不支持低功耗蓝牙"
        case .resetting: cause = "蓝牙模块正在重置"
        default: cause = "蓝牙不可用"
        }
        return "\(cause)，自动锁定已暂停；恢复后会自动继续。"
    }
}
