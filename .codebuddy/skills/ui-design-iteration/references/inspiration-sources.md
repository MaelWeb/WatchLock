# 参考来源清单（项目适配）

作者原文只说"浏览网页找喜欢的设计"，没有指定站点。这份清单是为 **macOS 原生 SwiftUI 应用**
这个具体场景整理的，并记录了各站点的**实际可抓取性**（实测日期 2026-10-20，用本环境 `web_fetch`）。

## 先说两条结论

1. **抓取工具只能拿到文字元信息（标题、作者、分类、链接），拿不到截图。**
   而这些站点几乎全是图片驱动的，所以自动抓取的价值是：**找方向关键词、找同类产品名、找可引用的链接**——
   视觉判断仍然要人看图。要么用户自己在浏览器看，要么把截图放进对话。

2. **Dribbble 这类站的产物大多是"渲染稿/网页稿"，不是原生控件。**
   直接用会把 macOS 原生界面带成 web 风，与项目规则 §2.1/§3（遵循 HIG、不自定义控件皮肤、禁止嵌套滚动）
   以及 `UI/Components/` 的既有形态相冲突。因此：**形态听 HIG，取向听这些站点**。

## 来源分层与可抓取实测

### 第一优先：真实同类 macOS App（形态与系统观感的**唯一**可靠来源）

真实上线的菜单栏/桌面工具才是原生控件长什么样子的依据。可抓官网与 Mac App Store 页面的**文字**
（功能分区、文案层级、卖点排序）；界面外观仍需用户提供截图或自己看。

候选（仅作为"找同类去对照"的索引，不预判它们的设计好坏）：
Stats、Itsycal、Raycast、Ice、Hidden Bar、AlDente、CleanMyMac、系统设置、控制中心。

作用：判断"这个信息该不该放进菜单栏面板""这类开关/滑块在原生里通常怎么摆"。

### 第二优先：Apple HIG（硬依据，可抓）

<https://developer.apple.com/design/human-interface-guidelines/>

- 文案可抓，适合在实现前核对：菜单栏应用的适用模式、控件尺寸、状态表达、无障碍。
- 项目规则已经要求"系统一致性"，HIG 是这条规则的依据来源，优先级高于任何灵感站。

### 图标资源：macOSicons（可抓，实测通过）

<https://macosicons.com/>

- 实测返回了图标名称、链接、上传者、日期（首页最新约 50 个），未被拦截。
- 用途：App 图标 / 菜单栏图标的风格与"同类产品用了什么母题"。
- 注意：菜单栏状态图标按项目规则用 `MenuBarIcon`，不要拿社区图标替换；这里只借风格判断。

### Dribbble（**需要人工**，自动抓取被拦）

- 实测：`https://dribbble.com/search/...` 返回人机验证页（"JavaScript is disabled… verify that you're not a robot"），
  拿不到任何作品信息。
- 价值仍然很高，但要换姿势：**由人在浏览器里看，把喜欢的那几张截图放进对话**。
- 用时只借：配色关系、层次、留白节奏、动效想法。**不借控件形态**。

### Behance（可抓，但关键词噪音大）

`https://www.behance.net/search/projects?search=<关键词>`

- 实测未被拦截，能读到前 24 条标题/作者/链接；更多需登录。
- **坑**：搜 `macos menu bar app` 时约 22/24 条是酒吧、餐厅品牌设计——"bar" 命中了酒吧。
  必须换精准词：
  - `macOS app UI`
  - `desktop app interface`
  - `menu bar app UI`
  - `macOS icon`
- 判断：搜出来的东西里同类占比低，说明这个词不行，换词而不是继续翻。

### Mobbin / Refero（**不覆盖 macOS**，本项目不用）

- Mobbin：定位是 "mobile & web apps"，抓到的页面里没有 macOS 或桌面端分类。有 MCP 接口但仅 Pro/Team，
  本项目未接入。实测首页可抓、无拦截，但只有营销文案。
- Refero：入口只有 Web apps / iOS apps / Styles(Beta)，同样没有桌面分类。首页可抓、无拦截。

结论：这两家对本项目的命中率低，别浪费轮次。除非将来做 iOS 配套端（见 `docs/watchos-companion-evaluation.md`）。

### Awwwards / Land-book / Godly（可抓，网页向，只借氛围）

- **Awwwards** <https://www.awwwards.com/>：实测可抓，返回 Site of the Day、获奖名单、合集、博客标题。
- **Land-book** <https://land-book.com/>：实测可抓，返回条目名/类型/作者/点赞，**但缩略图取不到**。
- **Godly** <https://godly.website/>：实测可抓但作品卡片信息基本没解析出来，只有导航与招聘。

这三个是 landing page / 营销站的审美，和 macOS 原生面板差得远。只借两样：
**动效与过渡的想法**、**色彩与氛围的基调**。不要照搬布局密度与字号。

### Pinterest（抓不到）

实测返回 "Pinterest doesn't work unless you turn on JavaScript"，页面是空壳。不用试。

## 检索姿势

- **一次一批，别一稿一改。** 呼应原文的强度谱系：同一目标下同时看几种截然不同的取向，再判断哪条谱系值得走。
- **具体链接 > 形容词。** 原文：clear examples are the best way to steer coding agents。
  给 agent 的是"参照 X 的 Y"，不是"高级一点""更现代"。
- **记录"借了什么"。** 每个参照都写清：来源链接 → 借的具体点（配色关系/层级/动效/氛围）。
  只写链接不写借什么，等于没记录。
- **借到什么程度要能说清。** 原文里有"几乎照搬"（明暗过渡）也有"看不出但受影响"（Sentry 的插图调性），
  两者都正当，但自己要知道是哪一种，免得无意中做出与来源高度雷同的设计。
- **不同来源给不同角色**：真实 Apple 应用 → 形态与克制程度；HIG → 硬约束；Dribbble/Behance → 色彩与打磨感；
  Awwwards 类 → 动效与氛围。混着用会互相打架。

## 搜索词清单（可直接用）

```
macOS app UI
menu bar app UI
desktop app interface
macOS settings panel
macOS icon design
status bar app
```

避开：`menu bar`、`bar app`、`toolbar` 这类会命中酒吧/餐厅的词（Behance 实测）。

## 已知限制

- 本文件的可抓取结论只代表 2026-10-20 这一次实测，站点随时可能改反爬策略；失败时按"需要人工截图"处理，不要反复重试。
- 所有站点都**看不到图**这件事是本环境的限制，不是站点的问题。需要看图时，请用户提供截图。
