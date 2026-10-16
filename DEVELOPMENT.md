# 开发文档（WatchLock）

面向贡献者：构建、打包、签名、调试与项目结构。产品介绍见 [README](./README.md)。

## 构建

```bash
swift build                     # 编译
swift test                      # 运行 Swift 单元测试
python3 -B -m unittest discover -s Tests/ReleaseTests -v  # 发布版本逻辑测试
./Scripts/build-app.sh          # 打包成 dist/WatchLock.app
open dist/WatchLock.app
```

### 打包开关

```bash
./Scripts/build-app.sh --debug              # debug 构建
./Scripts/build-app.sh --sandbox            # 打开 App 沙箱（仅沙箱兼容性对照；当前不以上架为目标）
./Scripts/build-app.sh --no-sandbox         # 关闭 App 沙箱（默认）
SIGN_IDENTITY="Apple Development: ..." ./Scripts/build-app.sh --debug
```

默认锁屏（模拟 ⌃⌘Q）与外部命令方式（`osascript`、`pmset`）依赖 Apple Events，沙箱下 `System Events` 会以 `-600 应用程序没有运行` 失败，所以默认关闭沙箱；可选的「系统接口」方式在进程内调用，不经 shell。

当前**仅通过 GitHub Release 分发，不发布到 App Store**。GitHub Actions 构建通用二进制并打包 DMG，默认使用 ad-hoc 签名（`SIGN_IDENTITY=-`），无需 Apple 证书、公证凭据或额外 GitHub PAT。Developer ID 签名与公证是后续降低 Gatekeeper 安装阻力的可选增强，不阻塞当前发布。

### GitHub Actions 发布

流水线：`.github/workflows/release.yml`，构建脚本：`Scripts/build-dmg.sh`。

- **自动版本发布（推荐）**：在 GitHub Actions 的「Build DMG and Release」选择「Run workflow」，选择默认分支（当前为 `main`），将 `release_type` 设为 `patch`、`minor` 或 `major`，`version` 留空。自动从最高已有稳定标签递增版本；无稳定标签时以 `Resources/Info.plist` 为基准。测试与 DMG 打包成功后，创建指向本次构建提交的注释标签，并在**同一次运行**中发布 GitHub Release。
- 例如已有 `v0.4.0`：`patch` → `v0.4.1`，`minor` → `v0.5.0`，`major` → `v1.0.0`。只识别无前导零的 `vmajor.minor.patch`；预发布、构建后缀及其他命名的标签不参与计算。若尚无标签且源码版本为 `0.1.0`，首次 patch 发布为 `v0.1.1`。
- **手动试包**：`release_type` 默认 `build-only`，可在 `version` 填写版本，留空读取 `Resources/Info.plist`。仅上传 artifact（保留 14 天），不会创建标签或 Release；可选择任意分支或标签。
- **已有标签发布**：仍支持手动推送 `v<版本>` 标签（例如 `v0.4.0`）触发流水线；`v0.4.0-beta.1` 等标签发布为 Pre-release，不标记为 Latest。
- 版本格式为 `major.minor.patch` 或 `major.minor.patch-prerelease`；不支持 `+build` 后缀。标签基础版本写入产物的 `CFBundleShortVersionString`，`github.run_number` 写入 `CFBundleVersion`；预发布后缀保留在 DMG 名称与 Release 标签中。不会修改源码里的 plist。
- 发布使用内置 `GITHUB_TOKEN` 的 `contents: write` 权限，不需要 PAT。此令牌创建的标签不会再触发另一轮标签流水线，故本次运行直接完成发布。仓库 / 组织规则需允许创建标签与 Release；构建 job 只有 `contents: read`。
- 发布流水线串行执行；构建失败不创建标签。标签包含本次 `run_id` 标记，重跑全部 job 时复用该标签并校验提交，不误递增新版本；每次运行尝试的 artifact 独立命名。标签冲突或提交不匹配时停止，不覆盖标签。
- 先创建草稿，上传两份文件成功后才公开 Release；发布失败可重跑原运行补齐草稿。已公开的 Release 不会被覆盖，再次发布同一版本会停止；修订请选择新的自动递增发布或新标签。
- DMG 包含 `WatchLock.app`、`Applications` 快捷入口与 `LICENSE`，应用资源目录也保留许可及 Required Notice。

本地运行相同打包链路：

```bash
SIGN_IDENTITY=- RELEASE_VERSION=0.4.0 BUILD_NUMBER=1 ./Scripts/build-dmg.sh --universal --no-sandbox
```

产物：`dist/WatchLock-0.4.0.dmg` 与 `dist/WatchLock-0.4.0.dmg.sha256`。使用 `shasum -a 256 -c WatchLock-0.4.0.dmg.sha256` 时需先进入 `dist/`。

当前 Release 包未进行 Developer ID 签名或 Apple 公证，签名校验只验证完整性，不代表已获 Apple 信任。macOS 可能拦截首次启动；用户确认来源及校验和后按系统提示在「隐私与安全性」中允许打开，受管理设备可能不允许。ad-hoc 包升级后可能需要重新授予蓝牙或辅助功能权限。

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
| `Resources/AppIcon.icns` | 应用图标（Dock / Finder / 关于页） |
| `Sources/WatchLock/UI/Design/MenuBarIcon.swift` | 五态状态图标本体（代码绘制，无位图资源），菜单栏与面板状态卡共用 |
| `Sources/WatchLock/UI/Design/StatusIcon.swift` | 面板状态卡的 SwiftUI 封装（复用 `MenuBarIcon`，20pt、语义色） |

改 logo 时：覆盖 `docs/logo/AppIcon-master.png` → 跑 `./Scripts/generate-icons.sh` 重新生成 `Resources/AppIcon.icns` → 提交产物（构建不再依赖本机图像工具）。
改菜单栏图标时：先改设计稿 `docs/ui-design/08-menubar-icons.html` 并覆盖渲染，再同步 `MenuBarIcon.swift` 的几何参数。

约定：

- **状态图标只画一份，两处共用**（`UI/Design/MenuBarIcon.swift`，由 logo 的「环形锁体 + 锁梁」提炼、代码绘制的模板图；五态：在身边 / 已离开 / 搜索中 / 已暂停 / 已关闭），要一眼看出状态，不直接用品牌 logo。设计稿见 `docs/ui-design/08-menubar-icons.html`。
  菜单栏用 `MenuBarIcon.image(for:)`；面板状态卡经 `UI/Design/StatusIcon.swift` 渲染同一张图，**不要再为面板另选 SF Symbol**（已移除 `ProximityStatus.symbolName`）。
- **品牌 logo 用于「身份展示」场景**（关于页等），走 `UI/Design/BrandLogo.swift`（`BrandLogoView`），找不到资源时回退 SF Symbol。
- 菜单栏图标必须是模板图（`isTemplate = true`，只用黑色 + alpha），系统才会按深浅色菜单栏自动着色；`MenuBarIconTests` 已校验。

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
- M3.5：UI 重构与品牌（含后续追加的状态卡图标同源、可选私有 API 锁屏、GitHub Release 分发决策）（设计 token 与组件库、菜单栏面板信息层级、设置窗口改自绘侧栏并把「高级」拆为「校准 / 诊断」、同轴阈值带、引导与校准向导重做、无障碍与破坏性操作确认）—— 已完成

- M4：GitHub Actions 通用 DMG 打包与 Release 流水线 —— 已实现，本地通用 DMG 与静态校验通过，首次云端执行待验证；本地化与帮助手册仍待完成，Developer ID 签名 / 公证为可选增强。

## 相关研究

- `docs/anti-false-lock-research.md` —— 误锁问题与 BLE 广播特性调研（阈值默认值的依据）
- `docs/watchos-companion-evaluation.md` —— 为什么本期不做 watchOS 配套 App
