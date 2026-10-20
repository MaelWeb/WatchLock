---
description: WatchLock 的 SwiftUI 界面开发规范（设计 token、组件复用、容器规则、无障碍）。改动 Sources/WatchLock/UI 下任何文件时适用。
globs: Sources/WatchLock/UI/**/*.swift
alwaysApply: false
---

# WatchLock UI 规范

设计依据见 `docs/ui-design.md`。本文件是编码时实际要遵守的硬性约束。

## 1. 设计 token 优先

禁止在视图里写裸数字。一律用 `WLTheme`（`UI/Design/WLTheme.swift`）：

- 间距：`WLSpacing.xxs/xs/sm/md/lg/xl/xxl` = 2/4/8/12/16/24/32
- 圆角：`WLRadius.sm/md/lg` = 6/10/14
- 颜色：`WLColor.success/warning/danger/neutral/accent`（**禁止**直接写 `.green` / `.orange` / `.red`）
- 卡片：`.wlCard()`；危险卡片：`.wlCard(tint: .danger)`；单行内容（开关行、提示条、指标瓦片）用
  `.wlCard(horizontal: WLSpacing.md, vertical: WLSpacing.sm)`（横 12 / 竖 8）
- 字体：`WLFont.statusTitle`（15）/ `WLFont.body`（13）/ `WLFont.caption`（11，配 `.secondary`）。
  **不要直接写 `.headline` / `.caption` 去凑设计稿字号**：macOS 上它们是 13 / 10，会整体偏小

## 2. 组件复用

`UI/Components/` 已有组件优先复用，不要就地重写：

| 组件 | 用途 |
| --- | --- |
| `MetricTile` / `MenuBarMetrics` | 指标瓦片（小标签 + 17 大数字 + 11 小单位，标签行可放附件如信号条）；读数换算一律走 `MenuBarMetrics`（无效值 →「—」） |
| `StatusIcon` | 五态状态图标（复用 `MenuBarIcon`，20pt + 语义色）；**面板里不要另选 SF Symbol** |
| `SignalMeter` | 4 格信号条，**按当前阈值动态分级** |
| `MetricRow` | 标签 + 数值（已带 `monospacedDigit`） |
| `WLButton` | `.primary` / `.secondary` / `.danger` 三档样式 |
| `WLButtonLabel` | 按钮标签外观；`Menu` 等不能直接用 `WLButton` 的控件用它保持同尺寸 |
| `ThresholdBand` | 在身边 / 已离开 同轴阈值带（带 clamp） |
| `DeviceRow` | 设备行（信号条 + 副标题 + 操作） |
| `StatChip` | 统计小卡 |
| `EmptyStateView` | 统一空态（基于 `ContentUnavailableView`） |
| `ScannerStatusBar` | 扫描 / 蓝牙 / 广播数状态行 |
| `FormCard` | 非 `Form` 页面的分组容器 |
| `ValueStepperRow` | `Form` 里的数值项：标签 … 数值 + 步进器；**数值项一律用它，不要把数字写进 `Stepper` 的标签句子**；单位文案走 `ValueFormat` |
| `StepIndicator` | 引导步骤进度（圆点，当前步骤为胶囊） |
| `OnboardingArt` | 引导顶部线稿插画；阶段由 `OnboardingArtStage.stage(forStep:bluetoothReady:)` 决定 |
| `RadioCard` | 竖排单选卡 |
| `SettingsDetail` | 设置详情区统一容器（内边距 + 最小宽度 + 滚动） |
| `BrandLogo` / `BrandLogoView` / `BrandLockup` | 品牌图标与「图标 + 名称」标识行；**菜单栏仍用状态图标，不用品牌 logo** |
| `CardSectionHeader` | 卡片内带图标的小标题 |
| `CardDivider` | 卡片内分隔线 |

## 2.1 macOS 控件陷阱（菜单栏面板踩过）

- **`Toggle` 在 `Form` 之外不会自动靠右**：`.switch` 样式会让开关紧贴文字。要把文字和开关分开摆，
  用 `Toggle(...).labelsHidden()` + 单独的 `Text`（装饰性小字加 `.accessibilityHidden`），开关自带的标题保留给 VoiceOver。
- **`Menu` 想要和按钮同款外观**：`.menuStyle(.button)` + `.buttonStyle(.bordered)`（+ `.menuIndicator(.hidden)`），
  标签用 `WLButtonLabel`。`.menuStyle(.borderlessButton)` 不会渲染按钮底，宽度也不跟随相邻按钮。
- **次要入口菜单**（如「更多」）用 `.menuStyle(.button)` + `.buttonStyle(.plain)` + 自绘标签，
  `.borderlessButton` 自带内边距会让它和卡片边缘对不齐。

## 2.2 系统玻璃材质（Liquid Glass）

依据与范围见 `docs/ui-design.md` §5.1.1。编码时遵守：

- **菜单栏面板不加自绘背景**：`MenuBarExtra(.window)` 的底由系统绘制，不要给 `MenuBarView` 加 `.background` /
  `NSVisualEffectView` 去盖它（Apple：popover 上应移除自定义背景，让系统材质生效）。
- **内容层不用 `glassEffect` / `Glass`**：卡片是内容，沿用 `.wlCard()` 的 `.quaternary` 填充；玻璃只留给系统控件层，不叠玻璃。
- **`Info.plist` 不设 `UIDesignRequiresCompatibility`**（设为 YES 会强制旧外观）；发布流水线用 `Scripts/verify-liquid-glass-sdk.sh` 校验 SDK ≥ 26。
- **自绘半透明层要响应「提高对比度」**：读 `@Environment(\.colorSchemeContrast)`，把透明度换算放进纯函数并写单测，
  默认档位必须与旧外观一致。（面板目前没有自绘半透明层，瓦片用 `.quaternary` 标准填充。）
- 以上只覆盖菜单栏面板；设置 / 引导窗口的材质另行评估。

## 3. 容器规则（硬性）

- **一个窗口内不得出现嵌套滚动**：不允许 `ScrollView` 里再放 `ScrollView` / 高度固定的 `List`。
- 内容超出一屏时，优先**拆分信息架构**（加侧栏页面），而不是塞滚动区。
- 窗口尺寸用 `.frame(minWidth:minHeight:)`，禁止固定 `frame(width:height:)` 锁死。

## 4. 阈值与信号（正确性约束）

- 阈值修改必须过 `ThresholdMath.clamp`，保证 `near − far ≥ 5 dBm`；不许直接写 `settings.nearRSSI = x`。
- 信号分级一律走 `SignalMeter.level(rssi:nearRSSI:farRSSI:)`，保证「看到的格数」与「会不会锁屏」一致。
- `RSSI = 127`（macOS 无有效信号）必须按「无信号」处理，等级 0。

## 5. 交互与无障碍

- 破坏性操作（解除绑定、清空日志、清除钥匙串密码）必须二次确认，并渲染为 `.danger` 样式。
- 所有按钮补 `.help()`；装饰性 `Image` 补 `.accessibilityHidden()`；`SignalMeter` 暴露 `accessibilityValue`。
- 数值一律 `.monospacedDigit()`。
- 不用固定 `frame(height:)` 包裹文本，避免破坏动态字体。
- 最小点击区域 ≥ 24×24pt。

## 6. 验收

改完跑 `swift build` + `swift test`。纯逻辑（clamp、信号分级、空态文案选择）必须落单元测试，UI 层不写 UI 测试。

## 7. 窗口样式：统一无标题栏

所有窗口（设置窗口、引导窗口）都**不用原生标题栏条**：隐藏标题文字 + 透明标题栏 +
`.fullSizeContentView`，红绿灯悬浮在内容之上（系统设置 / Finder 观感）。

- **窗口一律自建 `NSWindow`**（`SettingsWindow` / `OnboardingWindow`，`NSHostingView` 承载），
  **不要用 SwiftUI 的 `Settings` scene / `SettingsLink`**：系统创建的窗口事后再给 `styleMask`
  追加 `.fullSizeContentView` 不会让宿主视图重新铺满，内容停在标题栏下方，系统标题栏
  （底色 + 通栏分隔线）暴露出来，与内容色不一致。运行时改写系统窗口的 hack 已删除。
- 自建窗口必须在**创建时**带上 `.fullSizeContentView`，并设 `titleVisibility = .hidden`、
  `titlebarAppearsTransparent = true`、`titlebarSeparatorStyle = .none`（去掉标题栏下的通栏横线）。
- 不要用 `.windowStyle(.hiddenTitleBar)` —— 它会把红绿灯一起去掉，窗口就没法关闭了。
- 打开设置统一走 `SettingsWindow.present(session:)`（菜单栏按钮 + ⌘,）。
- **从菜单栏 popover 打开窗口必须延后一拍再前置**：应用是 accessory 策略且非前台，popover 还没收起时
  同步 `activate` 会被 macOS 14 协作式激活忽略，窗口会被其他 App 盖住。做法见
  `SettingsWindow.bringToFront`：`DispatchQueue.main.async` → 临时 `.floating` + `activate` +
  `orderFrontRegardless`，应用激活后恢复 `.normal`。新增任何由 popover 打开的窗口都照此处理。
- 顶部**不要手写 28~30pt 占位**：启用 `fullSizeContentView` 后 SwiftUI 自动给出安全区，
  内容自然避开红绿灯；只有自定义背景需要 `ignoresSafeArea(edges: .top)` 才能延伸到顶。
- 侧栏 / 详情区的内容都从安全区下方开始，不得与红绿灯重叠。
- 设置窗口**不要用 `NavigationSplitView`**：它自带工具栏（侧栏开关 + 标题），
  与透明标题栏叠加会在详情区顶部堆出一条空白。用 `SettingsView` 里的自绘侧栏
  （`HStack` + `SidebarButton`，侧栏底色用 `.background(.regularMaterial, ignoresSafeAreaEdges: .top)` 延伸到顶）。
- 需要贯通红绿灯条带的全高线条（如侧栏分隔线），画在窗口根视图的 `.background` 容器里并对该容器
  `.ignoresSafeArea()`；挂在子视图 `overlay` 里的 `ignoresSafeArea` 会被安全区布局限制，顶部会断。
- 详情列底色必须**单一来源**：对 Form / ScrollView 加 `.scrollContentBackground(.hidden)`，
  再用 `.background(Color(nsColor: .windowBackgroundColor), ignoresSafeAreaEdges: .top)` 整列铺色。
  否则滚动内容自带背景与顶部安全区条带是两种灰，会在安全区下缘出现横向接缝。

## 8. 设计稿只保留最新一份

`docs/ui-design/` 下每个界面**只有一份** `NN-<页面>.png` + 同名 HTML（共享 `mockups.css`）。

- 改了某个区域的界面 → 改对应 HTML → 重新渲染 → **直接覆盖同名 PNG**。
- **禁止**新增 `-v2`、`-new`、日期后缀的版本文件，也不要保留历史版本。
- 渲染命令（Chrome 无头，2x）：
  ```bash
  cd docs/ui-design && "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
    --window-size=1800,580 --screenshot=06-onboarding.png "file://$PWD/06-onboarding.html"
  ```
- 出图后要肉眼确认内容没有被裁切（画布高度不够就调大 `--window-size`）。
