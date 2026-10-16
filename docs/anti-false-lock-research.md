# 「手表在旁边却锁屏」问题：调研依据与修复评估

> 结论先行：上一轮修复**不是**在查阅官方文档与业界方案后做出的，而是基于代码走查 + 通用 BLE 经验推断的。本轮补齐调研后，**三个主要假设中有两个方向正确、一个表述错误**，并且暴露出一个此前没写进文档的**架构级约束**。

---

## 1. 调研得到的证据

| # | 来源 | 类型 | 关键结论 | 对本项目的意义 |
| --- | --- | --- | --- | --- |
| 1 | [Apple Developer Forums：CBPeer.identifier changes after OS update and device reboot on iOS 27（non-bonded BLE peripheral）](https://developer.apple.com/forums/tags/core-bluetooth)（2026-10） | 开发者一手报告 | 同一个**未绑定** BLE 外设，在 iOS 27 上系统升级后、以及**每次重启后**，`CBPeer.identifier` 都会变成不同的值；iOS 18 不会 | 「蓝牙地址轮换导致绑定 ID 失效」**属实**，我加的自动续接绑定逻辑有价值 |
| 2 | [Apple Developer Forums：IRK-resolvable BLE advertisements stops after screen turns off](https://developer.apple.com/forums/tags/core-bluetooth)（2026-09） | 开发者一手报告 | iPhone 息屏后，可被 IRK 解析的广播会停止；"当 Apple Watch 开机且处于连接状态时，iPhone 在息屏下仍可被 IRK 检测到" | Apple 设备的广播**随设备状态（屏幕/连接）动态开关**，而不是恒定广播；「收不到广播 ≠ 人走开了」**属实** |
| 3 | [Apple 官方《使用 Apple Watch 解锁你的 Mac》](https://support.apple.com/zh-cn/guide/mac-help/mchl4f800a42/15.0/mac/15.0) | 官方文档 | 前提是：同一 Apple 账户 + 双重认证、Mac 打开 Wi-Fi 与蓝牙、在「触控 ID 与密码」里打开开关、手表**已佩戴**且**已设密码** | Apple 自家方案建立在 **iCloud 身份 + Continuity（BLE/AWDL）** 之上，不是"扫描第三方可解析的广播" |
| 4 | [furiousMAC/continuity](https://github.com/furiousMAC/continuity)（US Naval Academy，PETS 2019 论文 *Handoff All Your Privacy*、ShmooCon 2020） | 逆向研究 | 已还原 Continuity BLE 广播线格式（Nearby Info / Nearby Action / Handoff / Proximity Pairing / Find My 等），并指出**即便使用随机 BD_ADDR 也能被跟踪** | Apple 设备（含手表）确实持续发出**可识别的 Continuity 广播**，比"按名称里有没有 watch"更可靠的识别证据是可行的 |
| 5 | 业界产品：Near Lock（已停止更新）、Unlox（前身 MacID） | 同类产品 | 都支持 **iPhone / iPad / Apple Watch** 作为信标，但都**需要配套的 iOS 端 App** | "用 Apple 设备做信标"是成熟路线，但**不是纯 Mac 单端**能做到的 |

## 2. 对既有修复的逐条评估

| 我上一轮的假设 / 做法 | 调研结论 | 处置 |
| --- | --- | --- |
| 未配对设备会轮换地址，`CBPeripheral.identifier` 会变 | **证实**（证据 1，虽然是 iOS 27 而非 macOS） | 保留自动续接绑定；注释改用证据化表述 |
| 手表与 iPhone 连接时广播被"系统节流" | **表述错误**。真实机制是 Apple 设备按屏幕/连接状态动态开关广播，且以 RPA + IRK 形式发出，第三方拿不到 IRK | 已修正代码与文档注释；保留「信号丢失保护」做法（结论仍成立，理由换掉） |
| 手表在桌前 RSSI 常年 -70 ~ -85 | **未实测**，属于我的估计 | 保留自动校准（它正是为此而生），但文档里标注为"待真机确认"，并在 UI 里直接显示实测值 |
| watchOS 后台广播受限（ADR-07 的理由） | **不充分**。论坛一手帖显示 watchOS 在 `HKWorkoutSession` 下能长时间维持 BLE **连接**；受限的是"广播"，我把两者混为一谈 | 已修正评估文档；ADR-07 结论（本期不实现）保留，理由改为成本 + 已有更好定位 |

## 3. 调研暴露出的架构级约束（此前没写进文档）

- Apple 官方的「用 Apple Watch 解锁 Mac」依赖 **iCloud 身份 + 双重认证 + Continuity**，第三方应用**无法获得**这层身份（无公开 API）。
- 因此纯 Mac 端 BLE 扫描只能做**"尽力而为"的在场判断**：识别靠启发式、距离靠 RSSI、广播还可能随时停。误锁不可能靠参数调到零。
- **正确定位**：本项目应作为「**离开即锁屏**」这一侧的补充（官方自动解锁只解决解锁，不解决离开锁屏），并在官方自动解锁不可用时提供降级；而不是试图复刻 Apple 的识别可靠性。
- 已据此新增 **ADR-08**。

## 4. 仍未解决、需要真机验证的事项

1. ~~**实测 RSSI 分布**~~ **已确认（2026-10-15 本机真机抓包，见 §7）**：手表贴近 Mac 时 RSSI 约 **-42 dBm**，远强于此前估计的 -70 ~ -85；默认「已离开」阈值 -70 **不至于**因阈值误锁。
2. ~~**Continuity 广播类型值**~~ **已部分确认（§7）**：手表与 iPhone 的 Continuity 类型**同为 0x10**，只靠类型字节**无法**区分手表；声明长度会随设备/状态变化，因此指纹只取类型字节，不再纳入长度。仍需更多样本才能固化「哪些类型算手表在场」，在此之前不写入任何类型语义常量。
3. **identifier 变化频率**：证据 1 是 iOS 27 的表现，macOS 上的频率未知，需观察日志里「手表蓝牙地址已轮换」的出现次数。
4. **Nearby Interaction / UWB**：Apple 官方的高精度测距框架，但仅 iOS/watchOS 可用、且要求配件端支持 UWB，Mac 无 UWB 芯片 → **不适用于本项目**。

## 5. 真机抓包记录（2026-10-15，本机）

用独立 BLE 扫描脚本（`/tmp/ble_scan.swift`，12 秒）在本机实测，共 **283 台设备**：

| 设备 | RSSI | 12 秒内广播次数 | 厂商数据 |
| --- | --- | --- | --- |
| `Zero@Apple Watch`（目标手表） | **-42** | 10 | `4c 00 10 05 27 98 d3 30 85` |
| `Mael@IPhone` | -40 | 2 | `4c 00 10 07 7d 1f fc bd d4 6e 28` |
| 其余 Apple 邻近广播 | -45 ~ -56 | 1 ~ 13 | 多为 `4c 00 10/09/0c/12/16 0x..` |

结论：

1. **手表可被持续、稳定地扫描到**，广播频率约每 1.2 秒一次；
2. **RSSI=127 不是常态**：本次 283 台、数千条广播中无一例无效 RSSI，说明「扫描到但无强度」是蓝牙栈的偶发状态，而非普遍行为；
3. **类型字节不唯一**：手表与 iPhone 同为 `0x10`，长度分别为 5 和 7，且 `0x10` 的长度在样本中覆盖 2~28 → 指纹只能取类型字节（已据此修正实现）；
4. **误锁主因修正**：既然手表在旁边时是 -42 而非 -70，原来的「默认阈值太严格」判断不成立；真正会误锁的是「一段时间内收不到任何有效样本 → 按信号丢失锁定」（已通过 `notePresence` 修复）。

## 6. 已选定路线：A（纯 Mac 单端 + 认广播类型）

| 已落地 | 说明 |
| --- | --- |
| `AppleAdvertisement` | 解析 Apple 厂商数据（`4C 00` + 类型字节 + 声明长度 + payload），产出类型指纹 `type=0x.. / len=..`；**只解析结构，不赋予语义** |
| 指纹参与续接 | 绑定时记录指纹，地址轮换后同名设备若广播类型不一致则拒绝续接（避免同名但不同类设备顶替）；解析不出指纹时退回仅凭名称，避免拒绝续接导致误锁 |
| 广播抓包入口 | 「设置 → 高级 → 广播抓包」展示候选设备的厂商数据与解析结果，可一键复制，用于真机固化识别规则 |
| 单元测试 | 10 例：解析、截断、指纹稳定性、非 Apple 数据、日志截断、指纹校验的三条路径 |

**下一步依赖真机数据**：请在手表就在旁边时打开「广播抓包」，复制内容发我；我会据此固化「哪些 Continuity 类型算手表在场」，把识别从「名称启发式」升级为「广播类型规则」。

## 7. 参考文献

1. Apple Developer Forums, Core Bluetooth 标签（identifier 变化、IRK 广播随息屏停止），2026。
2. Apple 支持，《使用 Apple Watch 解锁你的 Mac 和批准请求》（macOS 15 手册）。
3. Martin et al., *Handoff All Your Privacy – A Review of Apple's Bluetooth Low Energy Continuity Protocol*, PETS 2019；Celosia & Cunche, *Discontinued Privacy*, 及 furiousMAC/continuity 项目。
4. Near Lock、Unlox（MacID）同类产品。
