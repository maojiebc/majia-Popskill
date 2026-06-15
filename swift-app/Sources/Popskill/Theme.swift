import SwiftUI

// 账本视觉令牌 — 与 design_handoff README「Design Tokens」逐项对应。
// 全部为固定亮色，应用不跟随系统深色。

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

enum Ink {
    static let window = Color(hex: 0xFAFAF8)          // bg/window
    static let chrome = Color(hex: 0xF4F2EC)          // bg/chrome（标题栏/状态栏/弹层头尾/悬停）
    static let bundleHead = Color(hex: 0xF4F1E8)      // 套装卡头部
    static let bundleBody = Color(hex: 0xFCFBF6)      // 套装卡子项区
    static let card = Color.white                     // 独立能力卡、设置行
    static let hairline = Color(hex: 0xE8E6DF)        // 主要发丝线
    static let hairline2 = Color(hex: 0xEFEDE5)       // 卡内分隔
    static let control = Color(hex: 0xDCD9CF)         // 输入框边
    static let control2 = Color(hex: 0xD8D5CB)        // 次级按钮边
    static let ink = Color(hex: 0x111111)             // 主文字/主按钮底
    // v2.8 对比度修正（WCAG AA，对 #FAFAF8 底）：曾 7C7869=4.2:1、9A9684=2.8:1
    static let secondary = Color(hex: 0x74705F)       // 4.6:1
    static let secondary2 = Color(hex: 0x6F6B5E)
    static let tertiary = Color(hex: 0x807C6A)        // 4.0:1（11pt meta 行，大字标准）
    static let blue = Color(hex: 0x1F4ED8)            // accent
    static let amber = Color(hex: 0xB88300)
    static let amberText = Color(hex: 0x8A6400)
    static let amberBadgeBg = Color(hex: 0xF6ECC8)
    static let amberBadgeBorder = Color(hex: 0xE0CB84)
    static let red = Color(hex: 0xC01818)
    // 断链整卡（v2.13，设计稿 cardBroken/brokenBadge）
    static let brokenCardBg = Color(hex: 0xFDF4F4)
    static let brokenCardBorder = Color(hex: 0xE3A8A8)
    static let brokenBadgeBg = Color(hex: 0xFBEAEA)
    static let brokenBadgeBorder = Color(hex: 0xE8B4B4)
    static let brokenDesc = Color(hex: 0xA34440)     // 暗红描述（在 #FDF4F4 底过 AA）
    static let green = Color(hex: 0x1A9A4E)           // 同步点
    static let greenText = Color(hex: 0x1A6B35)       // 推荐方案文字
    static let greenBg = Color(hex: 0xF3F8F4)
    static let greenBorder = Color(hex: 0xBCD8C2)
    static let offGlyph = Color(hex: 0xA8A28F)        // v2.8：可点击状态格，1.7→3.1:1
    static let offDot = Color(hex: 0xC4BFB0)
    static let terminalBg = Color(hex: 0x16140F)
    static let terminalText = Color(hex: 0xC9C4B2)
    static let bannerBg = Color(hex: 0xFAF5E6)
    static let bannerBorder = Color(hex: 0xEFE3C8)
    static let highlight = Color(hex: 0xFDE68A)       // 搜索命中
    static let flashBg = Color(hex: 0xEEF4FF)         // 新装高亮
    static let monoDim = Color(hex: 0x5E5A4E)         // 状态栏等宽
    // 顶部统计条（v2.13）
    static let statGlyph = Color(hex: 0xB3AE9E)       // 类型 glyph（装饰）
    static let statOnLabel = Color(hex: 0x5E7A64)     // 「已激活」小标签（设计 #7C9A82 加深过 AA）
    static let tableHeadBg = Color(hex: 0xFAF9F5)     // 表格表头
    static let tableRowAlt = Color(hex: 0xFCFBF6)     // 表格套装子行
    static let tableHairline = Color(hex: 0xF1EFE8)   // 表格行分隔
}

extension Font {
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// 类型 tag 配色（描边式，Bundle 反白）
struct TypeTagStyle {
    let text: Color
    let border: Color
    let bg: Color

    static func of(_ t: CapType) -> TypeTagStyle {
        switch t {
        case .skill:  TypeTagStyle(text: Color(hex: 0x5A4A14), border: Color(hex: 0xC9B478), bg: .clear)
        case .agent:  TypeTagStyle(text: Color(hex: 0x1D3C63), border: Color(hex: 0x7FAACD), bg: .clear)
        case .mcp:    TypeTagStyle(text: Color(hex: 0x3C1D5A), border: Color(hex: 0xA98CC9), bg: .clear)
        case .cli:    TypeTagStyle(text: Color(hex: 0x1A4D33), border: Color(hex: 0x74B291), bg: .clear)
        case .bundle: TypeTagStyle(text: .white, border: Ink.ink, bg: Ink.ink)
        }
    }
}

// LinkStatus 视觉词汇（贯穿全应用）
extension LinkStatus {
    var glyph: String {
        switch self {
        case .on: "●"
        case .off: "—"
        case .stub: "◐"
        case .broken: "✕"
        }
    }
    /// 卡片 pill 里 off 用 ○（子项单元格用 —）
    var pillGlyph: String { self == .off ? "○" : glyph }
    var stateLabel: String {
        switch self {
        case .on: L("已激活")
        case .off: L("未链接")
        case .stub: L("占位")
        case .broken: L("断链")
        }
    }
    // PATCH-02 色语义：激活 = 绿（与同步指示统一），电光蓝收窄为纯交互色（聚焦/链接/焦点环）
    var color: Color {
        switch self {
        case .on: Ink.green
        case .off: Ink.offGlyph
        case .stub: Ink.amber
        case .broken: Ink.red
        }
    }
    var pillText: Color {
        switch self {
        case .on: Color(hex: 0x177A3E)
        case .off: Ink.tertiary
        case .stub: Ink.amberText
        case .broken: Ink.red
        }
    }
    var pillBg: Color {
        switch self {
        case .on: Ink.green.opacity(0.07)
        case .off: .clear
        case .stub: Ink.amber.opacity(0.05)
        case .broken: Ink.red.opacity(0.04)
        }
    }
    var pillBorder: Color {
        switch self {
        case .on: Color(hex: 0xA5D1B3)
        case .off: Ink.control
        case .stub: Color(hex: 0xDCC27A)
        case .broken: Color(hex: 0xE0A3A3)
        }
    }
}
