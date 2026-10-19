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
4. **Nearby Interaction / UWB**：Apple 官方的高精度测距框架。2026-10-19 复核更正：框架概述页标注 macOS 11.0+，但 `NISession` 类页的平台列表（来自搜索摘要，页面本身无法抓取）不含 macOS，两处标注不一致，**不能**再写成「仅 iOS/watchOS 可用」。结论仍为**不适用**，理由改为：交互需要两端设备都运行同一 App 并交换 discovery token，手表端要有配套 App（ADR-07 已决定本期不做），且需要双方具备 UWB 硬件；并非平台限制。待在浏览器复核两处平台标注。

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

## 6.1 外围探测复检（2026-10-19）

对「靠近 / 锁定」链路周边的系统探测做了一轮官方文档 + 本机（macOS 26.6.1）只读验证，结论如下：

| # | 发现 | 依据 | 处置 |
| --- | --- | --- | --- |
| 1 | 旧前置条件探测读 `com.apple.screensaver askForPassword`，在新系统上读不到 | 本机 `defaults read com.apple.screensaver` 仅有 `tokenRemovalAction`；社区报告 Sequoia 起该设置改由系统设置接管；`sysadminctl -screenLock status` 返回 `screenLock delay is immediate` | 改读 `sysadminctl`；输出文案取自其二进制字符串；无法识别时不判缺失 |
| 2 | 旧「手表已配对」探测靠 `system_profiler` 文本匹配 | 本机该条目在 `Not Connected` 分区，不代表在场；调用同步、结果永久缓存 | 改用 `LAContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithCompanion)`（macOS 15+，官方文档：找不到附近已配对设备返回 `LAErrorCompanionNotAvailable`；macOS 14 用 `...WithWatch`）。不弹界面，本机耗时 1–8ms |
| 3 | 会话锁定只靠非公开通知，漏一次「解锁」会一直跳过自动锁定 | 这是代码走查推断，**未复现**。`CGSessionCopyCurrentDictionary` 公开；`CGSSessionScreenIsLocked` 键未文档化，但存在于 `loginwindow` 二进制字符串中，本机解锁态下字典无此键 | 启动、唤醒、锁定前、自动解锁前用它校正；查询不到时不改状态 |
| 4 | 无 App Nap 防护 | Apple《Energy Efficiency Guide》：非前台、无窗口更新、无断言的应用是 App Nap 候选；用户发起的活动不会被 App Nap | 监听期间持有 `userInitiatedAllowingIdleSystemSleep` 活动。实测该选项不产生电源断言、`.userInitiated` 会产生 |

**待真机验证**（未做，不得当作结论）：
- `CGSSessionScreenIsLocked` 在**锁屏状态**下的取值；
- companion 策略在手表**走远 / 摘下**后是否变为不可用（本机只在手表就在旁边时观察到 true，所以它能否作为「在场」第二信号尚无证据，**未接入锁屏逻辑**）；
- 应用在没有 App Nap 防护时是否真的被限速（文档称 XPC 消息可使应用退出 App Nap，CoreBluetooth 走 XPC，影响可能小于预期）。

**已查但不采用**：Shortcuts「锁定屏幕」动作（`shortcuts run` 存在，但未找到 Apple 文档、本机也未核实动作存在）；Nearby Info 动作码 `0x0A Watch on wrist and unlocked`（来源为 iOS 10–12 时代逆向资料，页面未写半字节顺序，且与 §5 本机抓包的 `0x27` 对不上，不能落地）。

## 6.2 会议 / 演示豁免与解锁后重新布防的系统接口（2026-10-19）

均为本机（macOS 26.6.1）实测，结论只覆盖下列范围：

| 事项 | 实测结果 | 影响 |
| --- | --- | --- |
| `IOPMCopyAssertionsByProcess` 返回结构 | `[pid: [断言字典]]`，键含 `AssertType`、`AssertionTrueType`、`AssertLevel`（255 = 开）、`Process Name`、`AssertName`；类型常量 `PreventUserIdleDisplaySleep` 与 SDK 头文件 `IOPMLib.h` 一致 | 以此判定「有应用阻止显示器睡眠」 |
| 哪些命令产生该断言 | `caffeinate -d` 产生；`-i`、`-u` 不产生；`powerd` 常驻持有的是 `InternalPreventDisplaySleep`（类型不同） | 不会被系统自身误判；`caffeinate` 需显式忽略（用户主动保持唤醒） |
| 旧版 `NoDisplaySleepAssertion` | `AssertType` 保持原值，`AssertionTrueType` 归一为 `PreventUserIdleDisplaySleep` | 判定优先读 `AssertionTrueType` |
| **沙箱内是否可读** | 用与发布包相同 entitlements 签名的 `.app` 能读到他进程断言。**注意**：同样签名的裸命令行程序会以 133 退出，连 `print("hello")` 都不行，那不是沙箱拦截而是形态问题，不能据此下结论 | 发布形态下可行 |
| `CGEventSource.secondsSinceLastEventType(.combinedSessionState, …)` | 沙箱 `.app` 内可用，随时间递增 | 作为「键鼠空闲」判据 |

**未验证**：Zoom / Teams / Keynote / 浏览器会议等具体软件是否都持有该断言——只验证了接口和 `caffeinate`，没有在真实会议里观察；部分软件可能只在共享屏幕或播放视频时才持有。因此该选项默认关闭，并在设置页写明。

**设计取舍**：豁免有硬上限（默认 60 分钟，最大 240），到点无论如何都锁；查不到断言表时按「没有持有者」处理（照常锁屏）；不采用摄像头 / 麦克风占用判断（需要额外权限、隐私面更大）。重新布防用键鼠空闲而非固定延时，避免在用户操作中突然锁屏。

## 6.3 companion 策略能否作为「手表离开」信号（2026-10-19，本机实测）

方法：`Scripts/probe-companion.swift` 每秒采样 `deviceOwnerAuthenticationWithCompanion`、`CGSSessionScreenIsLocked` 与键鼠空闲秒数，仅在变化时落盘；同时间段 WatchLock 自身的诊断日志（蓝牙 RSSI、锁定事件）作为对照。时间为本地时间，采样 17:37–19:19，约 1 小时 40 分，一台 Mac、一块手表。

| 时间 | companion | 会话已锁 | 蓝牙侧同期事件 |
| --- | --- | --- | --- |
| 18:01:53 | true | 变为 true | 蓝牙判「离开」（RSSI -70，约 4.1 米），WatchLock 锁屏 |
| 18:02:34 | **变为 false** | true | 离开后约 41 秒 |
| 18:35:11 | **false** | 变为 false（已解锁，键鼠空闲 1 秒） | 蓝牙判「靠近」并解锁，用户就在电脑前 |
| 18:36:02 | false | 变为 true | 蓝牙判「离开」（RSSI -78）并锁屏，距上一行约 51 秒 |
| 18:37:41 – 18:39:34 | **true**（约 2 分钟） | true | 用户已离开、键鼠空闲 99–212 秒，蓝牙持续丢信号 |
| 18:52:40 – 18:53:34 | **true**（约 1 分钟） | true | 同上，空闲约 17 分钟 |
| 19:10:45 – 19:11:35 | **true**（约 50 秒） | true | 同上，空闲约 35 分钟 |
| 19:15:03 | true | true | 蓝牙「靠近」在 19:15:40，用户 19:15:44 解锁 |

结论（仅覆盖这台机器、这块手表、这一段时间）：

1. **不能作为「手表离开」的锁定信号**。它出现了两类相反的错误：用户已离开时多次变为 true（共 3 个窗口，累计约 4 分钟，其间屏幕已锁、键鼠长时间空闲、蓝牙持续丢信号）；用户就在电脑前时为 false（18:35:11 起至少约 50 秒，蓝牙为靠近、键鼠刚有操作）。
2. **响应慢**：18:01:52 蓝牙已判离开，companion 约 41 秒后才变 false，慢于现有蓝牙路径。
3. 它确实会随手表状态变化（不是常量），但从这份数据看不出变化由什么触发，不能当作「在场」的第二证据，也不能当作否决证据。变化原因（距离、手表唤醒 / 休眠、佩戴与解锁状态、与 iPhone 的连接等）**未能区分**。

**处理**：不接入锁屏逻辑；保持 ADR-11 的用途——只在「系统自动解锁」前置条件提示里使用，且探测结果不稳定时不应据此提示「缺失」。由于单次采样可能恰好落在 false 的窗口，前置条件提示只能写成「系统未报告……」，不能写成「未配对 / 未开启」（现有文案已是前者）。另注意：同时段的诊断日志里「未检测到与本 Mac 同一 iCloud 账户的 Apple Watch」是 `/Applications` 中已安装旧版本的文案（当前源码里已不存在该文案），不能拿它与上表的 companion 值比对。

**局限**：没有对用户真实位置做逐段标注（「离开」由锁屏、键鼠空闲、蓝牙丢信号三者推断），也没有做「摘下手表 / 锁手表」等受控动作；样本只有一台设备。要进一步区分触发原因，需要按下面的协议再采一轮：运行探测程序，记录每个动作的时间——摘下手表放在电脑旁、锁定手表、戴上不解锁、走远再回来、关闭 iPhone 蓝牙——再对照 companion 变化。

## 7. 参考文献

1. Apple Developer Forums, Core Bluetooth 标签（identifier 变化、IRK 广播随息屏停止），2026。
2. Apple 支持，《使用 Apple Watch 解锁你的 Mac 和批准请求》（macOS 15 手册）。
3. Martin et al., *Handoff All Your Privacy – A Review of Apple's Bluetooth Low Energy Continuity Protocol*, PETS 2019；Celosia & Cunche, *Discontinued Privacy*, 及 furiousMAC/continuity 项目。
4. Near Lock、Unlox（MacID）同类产品。
