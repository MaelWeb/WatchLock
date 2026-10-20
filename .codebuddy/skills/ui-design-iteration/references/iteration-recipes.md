# 迭代配方

标注说明：「原文」= 作者文中实际出现的内容；「项目适配」= 为本项目改写，非作者原话。

## 0. 原文里的真实 prompt（短、口语、直接）

```
mockups of a fun website for a dev tool

build a rollercoaster tycoon like contained component that I can actually play around with in an html — build two in parallel actually. one of them should have a transparent background

add a thin strip of maybe 200px height where we have a bunch of amusement park attractions in the same style as the rollercoaster
```

特点：
- 都很短，**不堆规范**；靠"same style as the rollercoaster"这类**指向已有元素的参照**来约束风格
- 敢于一次并行要两版（"build two in parallel"），其中一版变一个维度（如透明背景）
- 给出尺寸级的具体量（"maybe 200px height"），但不写实现细节

## 1. 批量生成 prompt 模板（项目适配）

一次要 4~10 稿，明确写出「哪些受约束、哪些放开」：

```
为一个 macOS 菜单栏 App「WatchLock」设计<界面名>。
产品一句话：<一句话说明，含母题>。

请输出 N 个互相不同的方案（每个一个独立 HTML 文件，共用 mockups.css）：
- 方案 1~N/2：严格遵循以下约束 —— <本项目 token / 容器规则 / 无障碍要求>
- 其余 N/2 个：放开玩，可以夸张、可以打破常规，用于提供思路

每个方案用一句话标注它的核心想法和它押注的取舍。
不要解释实现细节，直接给文件。
```

生成后**不要**立刻挑最好的，先扫一遍把"有火花的元素"摘出来（某个配色关系、某个信息层级、
某种过渡方式），再决定往哪个方向收敛。

## 2. 强度谱系 prompt（项目适配；原文只描述了做法，没有给 prompt）

```
沿用<方案 X>的方向，沿「极简 → 夸张」的谱系给出 5 个版本：
a) 只有文字和一个图形
b) 轻度图形化
c) 当前方案
d) 加入装饰性元素
e) 视觉优先，信息密度可以让路

每个版本标注它在谱系上的位置。
```

判断规则（原文）：整条谱系都不喜欢，多半是选错了谱系；另可借此判断该更极简，还是还有空间更疯。

## 2.5 风格探索稿 prompt（项目适配）

用户只有"想要更好看"、没有具体取向时用。和强度谱系的区别：轴是**设计取向**，不是复杂程度。

```
主题：<界面名>，母题：<一句话>。
请并行出 <4~6> 版风格取向明显不同的探索稿（每版一个 HTML，共用 mockups.css），
每版只押一个取向，不要把不同取向混在一版里：

a) 系统原生克制：看起来就像 macOS 自带设置面板
b) 工具感密度：信息紧凑、以数值与状态为主
c) 强状态色：用一块主色区域承载"当前是否安全"
d) 轻插画氛围：元素带一点手绘/图形化
e) （可选）极简：只留标题 + 一个状态图形

约束：都只用 WLTheme 的间距/圆角/字号档位；不得出现嵌套滚动；
不要把网页落地页的密度和字号带进来。

每版用一行说明：它押了什么、代价是什么。
```

看完后按 `references/inspiration-sources.md` 的分层判断：哪一版最接近"真实同类 macOS 应用"的手感。

## 3. fork 目录与索引（项目适配）

```
docs/ui-design/.scratch/
├── INDEX.md
├── 02-settings-general__a-blue-accent.html
├── 02-settings-general__b-tighter-density.html
└── 02-settings-general__c-wild-neon.html
```

命名：`<正稿文件名>__<这一稿改了什么>.html`，一眼能看出 fork 的差异点。

`INDEX.md` 格式（一行一稿，prompt 可节选）：

```markdown
| 文件 | 生成 prompt（节选） | 改了什么 | 结论 |
| --- | --- | --- | --- |
| 02-...__a-blue-accent.html | "把强调色从绿换蓝" | accent | 蓝与状态绿冲突，弃 |
```

**不要删除任何 fork。** 它们回答的是"为什么现在是这个样子"。

## 4. Playground（做法是原文；模板与导出文本框是项目适配）

`assets/playground.html` 复制到 `docs/ui-design/.scratch/` 后，改两处即可用：

1. `VARS` 数组：要调的 CSS 变量名、控件类型（color/range）、取值范围
2. 页面主体的设计稿片段（从正稿 HTML 里拷）

它做的事：

- 把 `VARS` 渲染成控件，实时写 `:root` 的自定义属性
- 底部文本框实时输出当前变量值，找到满意组合后**整体复制**回 `mockups.css` / `WLTheme.swift`

适合放进去调的变量：主色、窗口底色、侧栏材质色、卡片填充、分隔线、强调色、圆角、卡片内边距、字号。
**不适合**：布局结构、信息层级——那些属于 fork 层面，不是变量层面。

## 5. 出图对比（项目适配）

fork 与正稿都渲染成 PNG 后并排看（同一 `--window-size`，同 2x）：

```bash
cd docs/ui-design && "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
  --window-size=1800,580 --screenshot=.scratch/fork-a.png "file://$PWD/.scratch/fork-a.html"
```

输出 PNG **只放 `.scratch/`**，不进 `docs/ui-design/` 根目录。
