# 方法来源与出处对照

来源：Railcode《How our vibe coded website looks like a designer made it》
<https://railcode.dev/blog/vibe-coded-website>（作者 Yakko Majuri，Railcode 创始人）

作者不是设计师，用 coding agent 做出了常被追问"和哪位设计师合作"的官网。
全文是一次**创作流程复盘**，不是技术教程；他的目标是说明"可以借助 coding agent 做自己喜欢的、有品位的设计（tasteful = something you yourself like）"，并明确说不是认为设计师没必要。

已知限制：原文大量依赖截图，本次只读到文字，**配色值、布局等视觉细节未纳入**。

## 原文要点（按文章顺序）

1. **动机**：多数讨论聚焦 "LLM design slop"，作者却因 coding agent 而对设计更兴奋——以前无能为力，现在能把脑中的愿景变成现实。
2. **出发点**：Railcode = "code on rails"；上周发现自己和客户用起来都很开心；rails + fun = 过山车。
3. **灵感两来源**：浏览网页找喜欢的设计；让 agent 以不同风格批量生成某物的设计。目的是"open my mind"；多处取点子、组合、无尽迭代，大多是死路。
4. **首批过山车稿**：两个 ASCII 稿受朋友网站启发，其余交给 agent 发挥，作为灵感种子。
5. **强度谱系（Levels of intensity）**：沿强度/复杂度谱系出设计；若谱系上没有喜欢的，"probably I'm on the wrong spectrum"；也用来判断该更极简还是还有空间更疯。
6. **Go wild**：一个概念至少 4 版、有时 10 版；至少一半给一定指引，其余让 agent 放任。多半很糟，但提供新点子的火花。丑陋的霓虹稿把他从 ASCII 带向更有野心的方向。
7. **Rollercoaster Tycoon**：霓虹稿让他想起童年游戏，于是让 agent 做了可玩的迷你版（prompt：*"build a rollercoaster tycoon like contained component that I can actually play around with in an html — build two in parallel actually. one of them should have a transparent background"*）。试玩后觉得"太过"，退回单个过山车。
8. **孤立元素**：把过山车放进模板后觉得突兀（"wtf is a rollercoaster doing in the middle of this website"）→ "we needed a whole park"。
9. **游乐园条带**：放在 hero 底部（prompt：*"add a thin strip of maybe 200px height where we have a bunch of amusement park attractions in the same style as the rollercoaster"*）。放进网页仍很糟，迭代后变好：以过山车为锚设计各资产、逐个手挑并打磨动画、让条带不独立而成为到下一区块的**颜色过渡**。
10. **Fork**：已经很满意并给朋友看过，仍觉得不对，于是开始 fork。设计阶段始终单个 HTML，满意后才转成由 agent 并行编辑的 React 组件；原因是这样 fork/复制、改一两处、并排对比最快。
11. **Playground**：自己称之为 playgrounds，用来调颜色等变量。例：草地从蓝改绿后色调仍不对，于是做了调 accent/文字/草地/背景色的 playground。作者还想过做一个开源工具支持 forks 和 playgrounds。
12. **早期暴露于大量设计**：起初让 agent 做过"一个有趣的开发者工具网站"的 mockup，大多 slop，但后来想 CTA 时从中想起合适的设计。论点：早期多接触设计，即使很糟，后面可能找到宝。
13. **背景色**：白底不 fun → 天蓝 + 云，"makes a world of difference"。"Everything else followed… The hero dictated the rest of the site."
14. **接受自然出现的选择**：产品强调色是蓝，但网站的绿"happened so naturally"，于是接受，得到浅绿/深绿区块和泥土 footer；可能要回头调整产品设计。
15. **基调之后**：风格落定后，做新图标/资产都可以参照它；"get the vibe down"才有稳定方向。
16. **导航栏**：不该是静态色，改成随当前区块背景色变化；先试了白/浅蓝/浅绿/深绿四种静态版，最后发现"全都要"最好。
17. **灵感**：灵感对非设计师至关重要；"clear examples are also the best way to steer coding agents"。contextual.ai（明暗过渡，常拿来参照）、clay.com（某个 section 的灵感来源）、Sentry（风格完全不同，但持续看它来找"插图与内容结合"的感觉）。
18. **总结八条**：
    - 设计只用一家点名厂商的模型；认为另一家厂商的模型即使给了具体方向也很吃力；称 Fable 是其中最好的
    - 满意前所有东西留在一个 HTML 里，到要做文案之类才推进
    - 看很多网站，常回访喜欢的并不断找新的；特别喜欢某个组件就以它为底座
    - 起步让 agent 生成海量网站，约 99% 丢弃，偶尔捞出一个组件或新点子
    - 常让 agent "go wild"，也常让它把一个点子做成「极简 → 夸张」的多个版本
    - 喜欢有易取的过程轨迹，所以不断 fork、与原稿比较；可能继续在 fork 上做或回到原稿，**但从不删除任何 fork**
    - 做 playground 实时调颜色、字体、位置，而非走让 agent 修改的慢循环
    - 反复迭代，大多数迭代是死路
    - 最重要的：过程要开心

另：文章开头说为写这篇文章，他把每个原型和生成它的 prompt 整理进了一个索引，以便追溯过程——这是**事后为复盘做的**。

## Skill 内容的出处对照

| 类别 | Skill 中的内容 |
| --- | --- |
| 原文 | 有品位 = 自己喜欢；两种灵感来源；多看、持续看、喜欢的组件当底座；具体样例引导 agent；强度谱系；go wild（≥4 版、至少一半有指引）；并行出两版；单文件原型；fork 永不删；playground；孤立元素扩成语境；范围克制；资产以定稿元素为锚；目标情绪裁决；接受自然出现的选择；静态方案不对时随状态变化；基调先于细节；大多数迭代是死路；过程要开心 |
| 原文的轻度外推（措辞已收敛） | "保留方案与 prompt 的可追溯记录"（原文是事后整理 + 偏好有轨迹）；"觉得不对就 fork"（原文是该情境下的做法） |
| 项目适配 | `.scratch/` 与 `INDEX.md`；HTML 设计稿 → SwiftUI；`WLTheme.swift` 同步；`swift build/test`；渲染命令；触发词；反模式表中项目相关行；playground 模板；改写的 prompt 模板；"不引入 `#Preview`"；`inspiration-sources.md` 全篇（含站点清单、可抓取实测、搜索词、分层借用） |
| 有意与原文不同 | 见下 |

## 有意与原文不同

| 原文 | 本项目做法 | 原因 |
| --- | --- | --- |
| 点名只用某家厂商的模型 | 写成"一次多稿 + 优先视觉表现更好的模型" | 不把个人对具体厂商的主观经验固化成项目规范；原文自己也只是经验之谈 |
| fork 全部保留（原文未涉及仓库规则） | fork 放 gitignore 的 `.scratch/` | 项目规则 §8 要求 `docs/ui-design/` 只留最新一份 |
| 单文件 HTML → React | 单文件 HTML → SwiftUI | 技术栈不同 |
| 浏览器中调 playground | HTML playground，值写回 `WLTheme.swift` | 同上 |

## 曾被误写、现已更正的内容

首版 Skill 里有几处是我自己加的、却看起来像作者观点，已更正：
- "自家工具（Fable）"——原文没说 Fable 是谁家的工具，现按原文表述。
- "没有母题时多方案只会是通用模板的随机变体"、"先广度后收敛 = 先加法后减法"、"不好意思推翻"、"一次一稿最慢"——原文均无，已删除。
- "先定母题再画第一屏"——与原文过程不符（原文的点子是在迭代中长大/被推翻的），已改为"具象的出发点（允许被推翻）"。
- "99%"——原文指起步阶段的海量生成，首版误并到"一次 4~10 稿"，已更正。
- "整条谱系都不喜欢 = 方向错"——原文是 "probably"，已改为"多半"。
- "停止迭代的阈值（连续 3 稿…）"——原文无，且与"iterate, and iterate"的倾向相反，已从 recipes 删除。
