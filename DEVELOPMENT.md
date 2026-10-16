# 开发文档（WatchLock）

面向贡献者：构建、打包、签名、调试与项目结构。产品介绍见 [README](./README.md)。

## 构建

```bash
swift build                     # 编译
swift test                      # 运行单元测试
./Scripts/build-app.sh          # 打包成 dist/WatchLock.app
open dist/WatchLock.app
```

### 打包开关

```bash
./Scripts/build-app.sh --debug              # debug 构建
./Scripts/build-app.sh --sandbox            # 打开 App 沙箱（上架 / 沙箱兼容性对照）
./Scripts/build-app.sh --no-sandbox         # 关闭 App 沙箱（默认）
SIGN_IDENTITY="Apple Development: ..." ./Scripts/build-app.sh --debug
```

锁屏依赖外部命令与 Apple Events（`osascript` 模拟 ⌃⌘Q、`pmset`），沙箱下 `System Events` 会以 `-600 应用程序没有运行` 失败，所以本地真机测试默认关闭沙箱。

### 签名与权限为什么会「重新打包就失效」

「辅助功能」「蓝牙」授权是按应用的**签名要求（designated requirement）**绑定的：

| 签名方式 | designated requirement | 重新打包后授权 |
| --- | --- | --- |
| ad-hoc（`-`） | 二进制哈希 `cdhash`，每次构建都变 | **失效**（设置里看着还勾着，实际不生效） |
| Apple Development / Developer ID | Bundle ID + 证书（Developer ID 为 Team ID），稳定 | 保留 |

所以 `build-app.sh` 默认自动选本机的 `Developer ID Application` / `Apple Development` 证书，没有才退回 ad-hoc。
**第一次**从 ad-hoc 切换到证书签名时，需要重新授权一次辅助功能和蓝牙，之后重新打包不再丢。

若遇到「已勾选仍失败」：在「辅助功能」列表里选中 WatchLock 点「−」删除，再重新添加。

## 调试（无需真的走来走去）

不用真的来回走动也能端到端验证状态机与锁屏链路：

```bash
# 方式一：环境变量，启动即持续注入固定信号
WATCHLOCK_FAKE_RSSI=-85 dist/WatchLock.app/Contents/MacOS/WatchLock

# 方式二：设置 → 诊断 → 调试 → 打开「菜单栏『更多』里显示调试子菜单」
#         然后菜单栏 → 更多 → 模拟信号 → 选择 -50 / -65 / -85 dBm 或「信号丢失」
```

模拟期间真实广播被忽略；模拟触发的锁定同样会计入自动调参样本，可在「诊断 → 误锁反馈与自动调参」里点「恢复默认阈值」重置。

## 品牌资产

| 文件 | 用途 |
| --- | --- |
| `docs/logo/AppIcon-master.png` | 品牌主图（1024，圆角方形 + 渐变底 + 白色 w 锁形） |
| `docs/logo/MenuBarTemplate-source.png` | 菜单栏单色图源（w 锁形） |
| `Resources/AppIcon.icns` | 应用图标（Dock / Finder / 关于页） |
| `Resources/MenuBarTemplate.png` | 菜单栏模板图标（黑色 + alpha） |

改 logo 时：覆盖 `docs/logo/` 下的源图 → 跑 `./Scripts/generate-icons.sh` 重新生成 `Resources/` 下的产物 → 提交产物（构建不再依赖本机图像工具）。

约定：

- **菜单栏用状态图标**（`UI/Design/MenuBarIcon.swift`，由 logo 的「环形锁体 + 锁梁」提炼、代码绘制的模板图；五态：在身边 / 已离开 / 搜索中 / 已暂停 / 已关闭），要一眼看出状态，不直接用品牌 logo。设计稿见 `docs/ui-design/08-menubar-icons.html`。面板内状态卡仍用 SF Symbol（`ProximityStatus.symbolName`）。
- **品牌 logo 用于「身份展示」场景**（关于页等），走 `UI/Design/BrandLogo.swift`（`BrandLogoView`），找不到资源时回退 SF Symbol。
- 模板图标必须是「黑色 + alpha」，系统才会按深浅色模式自动着色；`generate-icons.sh` 已做归一化（兼容白底黑字与透明底黑字两种源图）。

## 项目结构

```
Sources/WatchLock/
├── App/           # 入口、AppDelegate、主控制器 AppSession
├── Core/
│   ├── Bluetooth/ # BLE 扫描与 Apple Watch 识别
│   ├── Proximity/ # RSSI 平滑与近/远状态机
│   ├── Lock/      # 锁屏执行
│   ├── Unlock/    # 唤醒 / 解锁策略
│   └── System/    # 睡眠唤醒监听、登录项
├── Storage/       # 设置持久化、钥匙串
├── Support/       # 诊断日志、通知与限流
└── UI/            # 菜单栏面板、设置窗口、首次启动引导
    ├── Design/    # WLTheme 设计 token（间距 / 圆角 / 语义色 / 字体）
    ├── Components/# 复用组件（信号条、阈值带、设备行、空态…）
    └── Settings/  # 设置窗口各页面（通用 / 设备 / 解锁 / 校准 / 诊断）
Tests/WatchLockTests/  # XCTest 单元测试
Resources/         # Info.plist、entitlements
Scripts/           # 打包脚本
docs/              # UI 设计稿（ui-design/）、调研与决策记录
REQUIREMENTS.md    # 需求规格说明书
```

## 约定

- UI 编码规范与窗口样式规则：`.codebuddy/rules/watchlock-ui.md`
- 设计稿：`docs/ui-design.md` + `docs/ui-design/*.png`（每个界面只保留最新一份，改稿直接覆盖同名文件）
- 提交前质量门：`swift build` 无警告 + `swift test` 全绿 + `./Scripts/build-app.sh` 打包成功

## 里程碑进度

- M1：扫描绑定、距离判定、自动锁定、菜单栏与设置界面、诊断日志、打包脚本 —— 已完成
- M2：唤醒解锁、通知（含 5 分钟限流）、开机启动、低耗电扫描、睡眠唤醒联动、首次启动引导、单元测试 —— 已完成
- M3：距离校准向导（FR-14）、误锁反馈与自动调参（FR-16）、调试用 RSSI 模拟（FR-17）、watchOS 配套 App 评估（结论：本期不实现）—— 已完成
- M4：UI 重构（设计 token 与组件库、菜单栏面板信息层级、设置窗口改自绘侧栏并把「高级」拆为「校准 / 诊断」、同轴阈值带、引导与校准向导重做、无障碍与破坏性操作确认）—— 已完成

## 相关研究

- `docs/anti-false-lock-research.md` —— 误锁问题与 BLE 广播特性调研（阈值默认值的依据）
- `docs/watchos-companion-evaluation.md` —— 为什么本期不做 watchOS 配套 App
