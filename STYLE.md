# Popskill —— 视觉设计语言

> 这是 Popskill 的 UI 设计参考。**主要灵感来源：[Surge for Mac](https://nssurge.com/)**，这是目前 Mac 上设计语言最像 App Store / 系统设置又有自己个性的第三方桌面应用。
>
> 工程师/设计师拿到这份文档应该：
> - 不需要看 Surge 截图也能写出风格一致的页面
> - 所有 design token（颜色/字号/圆角/间距）都能直接对应到 SwiftUI 代码
> - 看到一个新页面需求，能判断"这个在我们的设计语言里应该长什么样"
>
> **关键策略已通过本地 Surge.app teardown 验证**：
> - 字体：Surge bundle 自带的全是 Apple 系统字体（SF Compact / SF Mono），**零自定义字体** → 印证 §3
> - 色板：Surge 的 `Assets.car` 拆出 22 个唯一 named color，**零自定义 RGB，全是系统色的语义包装** → §2.5 落地为 Popskill 自己的 token
> - 框架：Surge 是 AppKit（一堆 `.nib`），我们走 SwiftUI——视觉规格通用但实现完全不同
>
> 最后更新：2026-05-12

---

## 目录

1. [设计原则](#1-设计原则)
2. [色板](#2-色板)
3. [字体](#3-字体)
4. [间距 / 圆角 / 阴影](#4-间距--圆角--阴影)
5. [窗口与背景](#5-窗口与背景)
6. [侧边栏](#6-侧边栏)
7. [卡片](#7-卡片)
8. [标题与分组](#8-标题与分组)
9. [大数据展示](#9-大数据展示)
10. [Tab 切换](#10-tab-切换)
11. [按钮](#11-按钮)
12. [模态 Settings 弹窗](#12-模态-settings-弹窗)
13. [图标系统](#13-图标系统)
14. [Popskill 五个页面的视觉应用](#14-popskill-五个页面的视觉应用)
15. [不抄什么](#15-不抄什么)

---

## 1. 设计原则

按重要性排序：

1. **像 Mac 原生 App，而不是网页**
   不写 Tailwind 那种"通用 UI"，写 SwiftUI 原生组件 + Apple HIG。
2. **彩色克制，留白慷慨**
   颜色只用在 section heading / 状态点 / CTA。大块面积是白 + 浅灰。
3. **关键数据用巨字号**
   比起堆图表，用"8 ms" / "412 calls" 这种直接的大字号数字。
4. **分组靠彩色标签，不靠分块色**
   每个内容 section 用一个彩色小标题（橙/绿/紫/蓝循环），而不是把整块背景染色。
5. **页面级开关放标题旁边**
   而不是埋在设置里。"Auto-update" 这种全局 toggle 直接挂 H1 旁。
6. **每个动作可逆，按钮态明确**
   主按钮蓝填充、次按钮白底描边、危险动作不强调红色。
7. **图标分两套各管一摊**
   线性单色 → 导航；拟物彩色 → 设置/分类入口。

---

## 2. 色板

### 2.1 基础色（直接用 SwiftUI 系统色，跨 light/dark 自动适配）

| 用途 | SwiftUI | HEX (light) |
|---|---|---|
| 主文本 | `.primary` | `#1C1C1E` |
| 次文本 | `.secondary` | `#8E8E93` |
| 三级文本 | `Color(.tertiaryLabel)` | `#C7C7CC` |
| 分隔线 | `Color(.separator)` | `#E5E5EA` |
| 卡片背景 | `Color(.controlBackgroundColor)` | `#FFFFFF` |

### 2.2 强调色

| 用途 | SwiftUI | HEX |
|---|---|---|
| 主 CTA / Toggle / Link | `.accentColor` (默认蓝) | `#007AFF` |

### 2.3 Section 彩色标签（循环使用）

> 每个内容 section 的小标题用一种彩色字号。**循环规则**：从上到下依次是橙 → 紫 → 蓝 → 绿，超出 4 个再回到橙。

| 名字 | SwiftUI | HEX |
|---|---|---|
| `sectionOrange` | `Color(.systemOrange)` | `#FF9500` |
| `sectionPurple` | `Color(.systemPurple)` | `#AF52DE` |
| `sectionBlue` | `Color(.systemBlue)` | `#007AFF` |
| `sectionGreen` | `Color(.systemGreen)` | `#34C759` |

### 2.4 状态色（用于小圆点 / 数字）

| 状态 | 色 | 用法 |
|---|---|---|
| 正常 / 启用 / 成功 | `.systemGreen` `#34C759` | 延迟 ms / 已启用 / 装好 |
| 等待 / 未配置 | `.systemOrange` `#FF9500` | 未设置 / 需要操作 |
| 失败 / 禁用 | `.systemRed` `#FF3B30` | 安装失败 / 网络错误（克制使用） |
| 中性 | `.secondary` | 已禁用 / 不适用 |

### 2.5 语义化 Design Token（从 Surge.app 拆解中学到的最重要一课）

**Surge 的真正智慧**：整套色板 **零自定义 RGB**，全部引用 macOS 系统色，但用语义化的 named color 包装一层。从 `Assets.car` 拆出的 22 个唯一命名（不算重复 light/dark variant）：

```
Surface  : ActivityCardBackground, MainViewBackgroundColor,
           TableHeader, Border, Separator
Text     : MainViewLabelColor, MainViewSecondaryLabelColor,
           MainViewTextColor
Sidebar  : SidebarHeader, SidebarTitle
Button   : ActivtyButtonBorder, SGMButtonHighlighted, SGMButtonHovered
Accent   : Cyan, Sky, Download
Brand    : MainIcon_Assets/Color-1 .. Color-5（仅用于主图标渐变）
```

**为什么这么干**：
- 改主题只改一个文件
- 跨 light/dark 自动适配（系统色天然支持）
- 让开发者写代码时**语义先于色值**——`.cardBackground` 比 `Color(hex: "#F8F8FB")` 更难写错

**Popskill 的等价 token**（在 `Design/PopskillColors.swift` 落盘一份）：

```swift
import SwiftUI

extension Color {
    // ─── Surface ─────────────────────────────────
    /// 主窗口背景（用 material 优先，这是 fallback）
    static let popMainBackground = Color(.windowBackgroundColor)

    /// 卡片背景
    static let popCardBackground = Color(.controlBackgroundColor)

    /// 表格头/工具栏背景
    static let popHeaderBackground = Color(.unemphasizedSelectedContentBackgroundColor)

    /// 分隔线
    static let popSeparator = Color(.separatorColor)

    /// 卡片/输入框边框
    static let popBorder = Color(.separatorColor).opacity(0.6)

    // ─── Text ────────────────────────────────────
    static let popLabel = Color(.labelColor)              // 主文本
    static let popSecondaryLabel = Color(.secondaryLabelColor)  // 副文本
    static let popTertiaryLabel = Color(.tertiaryLabelColor)    // 灰提示

    // ─── Sidebar ─────────────────────────────────
    /// 侧边栏 section heading (DISCOVER / MY LIBRARY)
    static let popSidebarHeader = Color(.secondaryLabelColor)

    /// 侧边栏 item label
    static let popSidebarTitle = Color(.labelColor)

    // ─── Button States ───────────────────────────
    /// 鼠标 hover 时的 fill（按钮、列表行）
    static let popHoverFill = Color(.controlAccentColor).opacity(0.08)

    /// 按下/选中时的 fill
    static let popHighlightFill = Color(.controlAccentColor).opacity(0.16)

    // ─── Section Accents（循环色）────────────────
    /// section heading 用的 4 色循环
    static let popSectionAccents: [Color] = [
        .orange, .purple, .blue, .green
    ]

    // ─── Status ──────────────────────────────────
    static let popStatusOK = Color.green
    static let popStatusWarning = Color.orange
    static let popStatusError = Color.red
    static let popStatusNeutral = Color(.secondaryLabelColor)
}
```

**用法范式**：

```swift
// ❌ 别这么写
RoundedRectangle(cornerRadius: 16)
    .fill(Color(hex: "#FFFFFF"))

// ✅ 这么写
RoundedRectangle(cornerRadius: 16)
    .fill(Color.popCardBackground)
```

这样：
- 改主题只改 `PopskillColors.swift` 一个文件
- Dark mode 自动适配（系统色天然支持）
- 代码 review 时"违反设计语言"一眼可见——任何 `Color(hex: ...)` 都是 red flag

### 2.6 渐变背景

窗口主背景用浅紫到浅蓝的对角渐变：

```swift
LinearGradient(
    colors: [Color(hex: "#F4F5FA"), Color(hex: "#ECEEF8")],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)
```

但**优先用 SwiftUI 原生 material**（自动跟随系统亮暗 + 透明效果）：

```swift
.background(.regularMaterial)   // 或 .ultraThinMaterial
```

---

## 3. 字体

全部用 SwiftUI 系统字体（SF Pro），不引入自定义字体。

| 用途 | SwiftUI | pt 估值 | weight |
|---|---|---|---|
| Page Title (H1) | `.system(.largeTitle)` | 28-34 | `.bold` |
| Section Heading (彩色) | `.system(.subheadline)` | 13-15 | `.semibold` |
| 卡片标题 | `.system(.headline)` | 16-17 | `.semibold` |
| 卡片副文本 | `.system(.subheadline)` | 13-15 | `.regular` |
| 大数据数字 | `.system(.largeTitle)` + 自定义 size | 48-64 | `.bold` |
| 数字单位 | `.system(.title3)` | 18-20 | `.medium` |
| Body | `.body` | 15-17 | `.regular` |
| Caption | `.caption` | 11-12 | `.regular` |

**关键点**：
- 大数字用 `.rounded` design 看起来更现代（SF Pro Rounded）：
  ```swift
  Text("412")
      .font(.system(size: 56, weight: .bold, design: .rounded))
  ```
- 不要乱混 `.serif`/`.monospaced`，除非展示代码片段或 hash 串。

---

## 4. 间距 / 圆角 / 阴影

### 4.1 间距（基于 8pt 网格）

| 名字 | pt |
|---|---|
| `xs` | 4 |
| `sm` | 8 |
| `md` | 16 |
| `lg` | 24 |
| `xl` | 32 |
| `2xl` | 48 |

**最常用**：
- 卡片内边距：16 (`md`)
- 卡片之间间距：16-24 (`md`–`lg`)
- 内容区到窗口边：24-32 (`lg`–`xl`)

### 4.2 圆角

| 用途 | radius |
|---|---|
| 大卡片（Activity 那种） | 20 |
| 中卡片（Library row、Detail subsections） | 16 |
| 小卡片 / 内嵌 box | 12 |
| 按钮 | 8 |
| 胶囊 Tab | `.infinity`（或者用 `Capsule()`） |
| Toggle | iOS 默认 |

### 4.3 阴影

**默认不加 shadow，靠卡片自身白底 + 背景渐变区分层次**。需要时用极轻阴影：

```swift
.shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
```

胶囊 Tab 的选中态可以加个稍微明显一点的：

```swift
.shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 1)
```

---

## 5. 窗口与背景

### 5.1 窗口框架

- 标准 macOS 窗口（traffic light 在左上）
- 最小尺寸：1100 × 720
- 默认尺寸：1280 × 800

### 5.2 背景

主窗口背景 = `.regularMaterial` 或浅渐变（见 §2.5）。

**侧边栏背景**：
```swift
.background(.regularMaterial)   // 跟主窗口对比稍微浅一点的 material
```

或者用 SwiftUI 标准 `NavigationSplitView`，它会自动给侧边栏正确 material。

---

## 6. 侧边栏

### 6.1 结构

```
[App Logo / 名字]    ← 可选

DISCOVER             ← section heading, 灰小字 caps
  ✨ Featured         ← 单色 SF Symbol + 文字
  📂 Categories
  📊 Top Charts

MY LIBRARY
  📦 Installed (47)   ← 数字小 badge
  ⬇ Updates  ●3       ← 蓝点 badge
  🕐 Recently Used
  ☁ Stubs (12)

INSIGHTS
  📈 Usage
  💰 Token Spend
  💤 Idle Candidates

─────                  ← 分隔线

⚙ Settings
☁ WebDAV Sync
```

### 6.2 SwiftUI 实现要点

```swift
NavigationSplitView {
    List(selection: $selection) {
        Section("DISCOVER") {
            Label("Featured", systemImage: "sparkles")
            Label("Categories", systemImage: "square.grid.2x2")
            Label("Top Charts", systemImage: "chart.bar")
        }
        Section("MY LIBRARY") {
            Label("Installed", systemImage: "shippingbox")
                .badge(47)
            Label("Updates", systemImage: "arrow.down.circle")
                .badge(3)
            // ...
        }
        // ...
    }
    .listStyle(.sidebar)
} detail: {
    // 当前页内容
}
```

### 6.3 设计要点

- Section heading 用 `Section("文字")` 自动渲染，**不需要手写彩色**——SwiftUI 在 sidebar 里默认是灰小字 CAPS
- 图标用 SF Symbols 单色，**不在侧边栏用彩色图标**
- Badge 用 `.badge(Int)`，数字超过 99 SwiftUI 会自动显示 "99+"
- 选中态 SwiftUI 自动处理（圆角高亮背景）

---

## 7. 卡片

### 7.1 标准卡片

```swift
VStack(alignment: .leading, spacing: 12) {
    // 标题区
    HStack {
        Text("Card Title").font(.headline)
        Spacer()
        // 可选：toggle 或 menu button
    }
    // 描述
    Text("Card description goes here").foregroundStyle(.secondary)
    // 内容
}
.padding(16)
.background(Color(.controlBackgroundColor))
.clipShape(RoundedRectangle(cornerRadius: 16))
```

### 7.2 卡片变体

| 类型 | 用处 | 关键差异 |
|---|---|---|
| **Stats 卡片** | Activity / Insights 头部 | 标题在顶部小字，数据在中间巨字号 |
| **Setting 卡片** | Discover/Settings 页 | 右上角 toggle，左下角状态点 + 文字 |
| **List Row 卡片** | Library 列表每行 | 横向 layout：头像 + 名字 + 副信息 + 行内 toggle |
| **Action 卡片** | Updates 页每个更新 | 主信息 + 右下角 [Update] 按钮 |

### 7.3 状态指示器（卡片左下角）

```swift
HStack(spacing: 6) {
    Circle()
        .fill(Color.systemOrange)
        .frame(width: 8, height: 8)
    Text("未设置")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

---

## 8. 标题与分组

### 8.1 Page Title

```swift
HStack {
    Text("HTTPS 解密")
        .font(.largeTitle.bold())
    Toggle("", isOn: $enabled)        // 标题旁开关
        .toggleStyle(.switch)
        .labelsHidden()
    Spacer()
    // 顶部右侧的其他按钮
}
.padding(.horizontal, 32)
.padding(.top, 24)
.padding(.bottom, 16)
```

### 8.2 Section Heading（彩色）

```swift
Text("CA 证书")
    .font(.subheadline.weight(.semibold))
    .foregroundStyle(Color.systemOrange)
    .padding(.bottom, 8)
```

**循环色顺序**（在同一个页面里，第 1 个 section 橙、第 2 个紫、第 3 个蓝、第 4 个绿，再 5 个回到橙）：

```swift
let sectionColors: [Color] = [.systemOrange, .systemPurple, .systemBlue, .systemGreen]

// 用法
ForEach(Array(sections.enumerated()), id: \.offset) { idx, section in
    SectionView(
        title: section.title,
        color: sectionColors[idx % sectionColors.count]
    )
}
```

### 8.3 Section 之间的分隔

不用 `Divider()`。靠**间距 + 彩色标题**自然分组。如果一定要分隔线，用：

```swift
Divider().opacity(0.5)
```

---

## 9. 大数据展示

### 9.1 单数据卡片

```swift
VStack(alignment: .leading, spacing: 8) {
    HStack {
        Text("Total Calls")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        Spacer()
        Text("Last 30 days")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }
    Text("1,247")
        .font(.system(size: 56, weight: .bold, design: .rounded))
        .foregroundStyle(.primary)
    // 可选：底部 mini chart 或对比数字
}
.padding(20)
.frame(maxWidth: .infinity, alignment: .leading)
.background(Color(.controlBackgroundColor))
.clipShape(RoundedRectangle(cornerRadius: 16))
```

### 9.2 关键数字配色

- 数字本身永远黑色 / `.primary`，**不要给数字本身染彩色**（保持权重感）
- 状态用旁边的小标签或圆点表达，不染数字
- **唯一例外**：延迟 ms 类高频读取的数据可以染绿（Surge 的策略页就这么做）

### 9.3 mini chart

Activity 页那种"上传 208 B/s + 下方一条折线"的效果，用 SwiftUI Charts：

```swift
import Charts

Chart(dataPoints) { point in
    LineMark(
        x: .value("Time", point.t),
        y: .value("Rate", point.v)
    )
    .foregroundStyle(.systemPurple)   // 跟卡片色调呼应
}
.frame(height: 32)
.chartXAxis(.hidden)
.chartYAxis(.hidden)
```

---

## 10. Tab 切换

胶囊样式 segmented control：

```swift
Picker("", selection: $tab) {
    Label("直接连接", systemImage: "arrow.left.arrow.right").tag(Tab.direct)
    Label("全局代理", systemImage: "globe").tag(Tab.global)
    Label("规则判定", systemImage: "list.bullet.indent").tag(Tab.rule)
}
.pickerStyle(.segmented)
```

或者自定义胶囊样式（选中态白底 + 阴影）。**优先用 `.segmented` 系统样式**，自动跟随主题。

---

## 11. 按钮

### 11.1 主按钮（CTA）

```swift
Button("Install") { /* ... */ }
    .buttonStyle(.borderedProminent)
    .controlSize(.large)
```

### 11.2 次按钮（白底描边）

```swift
Button("What's New") { /* ... */ }
    .buttonStyle(.bordered)
```

### 11.3 链接按钮（无填充）

```swift
Button("github.com/foo/bar") { openURL(...) }
    .buttonStyle(.link)
```

### 11.4 菜单按钮（卡片右下角的 ⋯）

```swift
Menu {
    Button("Stub", action: stub)
    Button("Uninstall", action: uninstall)
} label: {
    Image(systemName: "ellipsis.circle")
        .foregroundStyle(.secondary)
}
.menuStyle(.borderlessButton)
```

---

## 12. 模态 Settings 弹窗

用于"配置管理"、"通用设置"这种二级深度操作。

### 12.1 结构

```
┌─────────────────────────────────────┐
│ 通用                              ⊗ │
│ 可以在这里找到大部分基础配置        │
├─────────────────────────────────────┤
│   [Tab1] [Tab2] [Tab3]              │
│                                     │
│   字段 A:  [输入框]                 │
│   字段 B:  [选择器]                 │
│   ──────                            │
│   字段 C:  [按钮]                   │
│   ...                               │
├─────────────────────────────────────┤
│                    [取消] [应用]    │
└─────────────────────────────────────┘
```

### 12.2 SwiftUI 实现

用 `.sheet(isPresented:)` 显示，内容用 macOS 14+ 的 `Form` 嵌入：

```swift
.sheet(isPresented: $showSettings) {
    SettingsSheet()
        .frame(minWidth: 600, minHeight: 500)
}

struct SettingsSheet: View {
    var body: some View {
        VStack(spacing: 0) {
            // 顶部标题区
            VStack(alignment: .leading, spacing: 4) {
                Text("通用").font(.largeTitle.bold())
                Text("可以在这里找到大部分基础配置")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            Divider()

            // 内容区
            Form {
                // ...
            }

            Divider()

            // 底部按钮区
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("应用") { apply(); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
            }
            .padding()
        }
    }
}
```

---

## 13. 图标系统

### 13.1 两套并存（重要）

**A. 导航 / 元数据图标 = 单色线性 SF Symbols**

- 侧边栏入口图标
- 卡片标题旁的小图标
- 按钮内嵌图标

```swift
Image(systemName: "shippingbox")
    .foregroundStyle(.primary)
```

**B. 设置入口 / 分类入口 = 彩色拟物图标**

模仿 macOS System Settings / iOS Settings 那种"每个图标是个小应用"的风格。

- 用 SF Symbols 加 `palette` rendering mode 实现彩色
- 或者自己设计 SVG（v2 再考虑）

```swift
Image(systemName: "person.crop.circle.fill")
    .symbolRenderingMode(.palette)
    .foregroundStyle(.white, .systemBlue)
    .font(.system(size: 48))
    .frame(width: 64, height: 64)
    .background(LinearGradient(...))
    .clipShape(RoundedRectangle(cornerRadius: 14))
```

### 13.2 Skill 头像（v1）

按 PLAN.md D13 决策：**首字母 + hash 到固定底色**。

```swift
struct InitialAvatarView: View {
    let name: String
    var size: CGFloat = 48

    private var initial: String {
        String(name.prefix(1).uppercased())
    }

    private var color: Color {
        // hash name → 8 个候选色之一
        let palette: [Color] = [.systemRed, .systemOrange, .systemYellow,
                                .systemGreen, .systemTeal, .systemBlue,
                                .systemIndigo, .systemPurple]
        let idx = abs(name.hashValue) % palette.count
        return palette[idx]
    }

    var body: some View {
        Text(initial)
            .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient)         // SwiftUI 自动渐变
            .clipShape(RoundedRectangle(cornerRadius: size * 0.25))
    }
}
```

`.gradient` 是 SwiftUI 5+ 的神器，自动从一个 Color 生成"上深下浅"的微妙渐变，比单纯 `.fill(color)` 立体感强 10 倍。

---

## 14. Popskill 五个页面的视觉应用

### 14.1 Featured 页

布局：竖向 ScrollView
- 顶部 Hero（彩色渐变背景 + 白字 + Install 主按钮）
- 接下来 3-4 个横向滚动 carousel（每个 carousel 一个彩色 section heading）

Section 配色（按出现顺序）：
1. 🔥 New This Week — `.systemOrange`
2. 📈 Top Installed — `.systemPurple`
3. 🎯 Curated for You — `.systemBlue`
4. 🛠 Developer Tools — `.systemGreen`

### 14.2 Library 页

布局：竖向 List，每行是个 RoundedRectangle 卡片
- Row 横向：[头像 48px] [名字 + 副信息(2 行)] [行内 3 个 toggle] [⋯ 菜单]
- 每行高度 ~72-80pt
- 顶部 Tab："All / Active / Inactive / Stub"（segmented control）
- 顶部右侧搜索框（自动 .searchable modifier）

### 14.3 Detail 页

布局：竖向 Form，几个明确 section（每个用彩色 heading 区分）
1. **基本信息**（橙）：头像 + 名字 + 作者 + 版本 + 星数
2. **启用范围**（紫）：三个 toggle for Claude/Codex/Gemini
3. **描述**（蓝）：README 渲染（swift-markdown-ui）
4. **使用情况**（绿）：你的使用统计 mini view
5. **版本历史**（橙）：list of versions
6. **来源**（紫）：GitHub repo link

### 14.4 Updates 页

布局：竖向 List，类似 Library 但每行 Action 是 [Update] 按钮
- H1 旁边放"Auto-update is ON · Check every 6h"toggle
- 顶部右侧 "Update All (3)" 主按钮

### 14.5 Insights 页

布局：竖向 ScrollView，**最重 Stats 卡片**
- 顶部：3 个 Stats 大卡片（Total Calls / Tokens / Cost）横排
- 中部：Top by Frequency 条形图
- 下部：Token Hogs 饼/条
- 底部：Hibernate Candidates 列表（每项右边一个 [→ Stub] 按钮）

期间筛选器（"Last 30 days" 下拉）放 H1 旁。

---

## 15. 不抄什么

Surge 的某些设计对我们不适用，**明确不学**：

| Surge 有的 | 我们不要 | 理由 |
|---|---|---|
| 顶部右上角"系统代理 / 增强模式"全局开关条 | 不要 | 我们没有那种系统级 always-on 状态 |
| 嵌入式"面板"（Surge 主窗口底部独立的内嵌窗口） | 不要 | 我们的 Stats 不需要常驻显示 |
| 多种密度并存的页面（表格 + 卡片 + 网格混着用） | 弱化 | 每个页面只用一种主布局 |
| 复杂的中间人代理证书 UI | 不需要 | 我们没有 MitM 相关需求 |
| Profile / 配置式切换 | 不需要 | 我们没有"多套配置切换"的概念 |

---

## 附录 A：SwiftUI 设计 token 落地建议

建议在项目里创建 `Design/` 目录，统一收纳：

```
swift-app/Popskill/Design/
├── DesignTokens.swift     ← 颜色、间距、圆角常量
├── Section+Color.swift    ← Section heading 循环色辅助
├── CardStyle.swift        ← ViewModifier，统一卡片样式
└── Theme.swift            ← 主题切换（v1 只有 light）
```

示例 `CardStyle.swift`：

```swift
struct PopskillCardStyle: ViewModifier {
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension View {
    func popskillCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(PopskillCardStyle(cornerRadius: cornerRadius))
    }
}

// 用法
VStack { ... }
    .popskillCard()
```

---

## 附录 B：何时更新这份文档

- 决定加 dark mode → 把 §2 色板补全 dark variant
- 加入设计稿审查流程 → 顶部加一个"待定"节
- 引入第三方组件库（不推荐）→ 写一节说明集成方式
- v1 上线后用户反馈 UI 不像 Mac App → 检查违反了哪条 §1 原则，加 Rev N 记录

---

## 引用

- Surge for Mac：https://nssurge.com/
- Apple Human Interface Guidelines (macOS)：https://developer.apple.com/design/human-interface-guidelines/macos
- SF Symbols：https://developer.apple.com/sf-symbols/
- SwiftUI 系统色：https://developer.apple.com/documentation/swiftui/color
