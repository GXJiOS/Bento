import SwiftUI
import AppKit

/// 设计令牌 —— 与 toolbox-design/prototype.html 的「规范」页 1:1 对应。
///
/// 视觉语言：macOS Ventura+ 系统设置那套 —— 次级灰底 + 浮起圆角卡片 + 分类语义色。
/// 颜色分两类：
///   1. 语义色（accent / separator / label / system*）直接读系统，自动适配主题与用户偏好；
///   2. 层次色（灰底 / 卡片 / 凹槽）系统没有正好的语义（dark 下 controlBackground 比
///      underPage 更深，与「卡片浮在灰底上」相反），所以用 dynamicProvider 写死原型调好的值。
enum Tokens {

    // MARK: - 尺寸（pt）

    static let toolbarH: CGFloat = 56
    static let sidebarW: CGFloat = 242
    static let sidebarMinW: CGFloat = 200
    static let sidebarMaxW: CGFloat = 340

    static let winRadius: CGFloat = 12
    static let cardRadius: CGFloat = 12
    static let ctlRadius: CGFloat = 7

    static let padContent: CGFloat = 14   // 灰底内距
    static let gapCard: CGFloat = 12      // 卡片间距
    static let padCard: CGFloat = 14      // 卡片内距

    static let itemH: CGFloat = 30        // 侧栏工具项
    static let sectionH: CGFloat = 26     // 侧栏分类头
    static let optionBarH: CGFloat = 48
    static let cardHeadH: CGFloat = 38
    static let cardFootH: CGFloat = 42
    static let rowH: CGFloat = 36         // 结果行

    static let iconSmall: CGFloat = 22    // 侧栏分类图标方块
    static let iconLarge: CGFloat = 27    // 工具栏标题图标方块

    static let paletteW: CGFloat = 684
    static let paletteInputH: CGFloat = 62
    static let paletteRowH: CGFloat = 44
    static let paletteRadius: CGFloat = 16

    static let menuBarPanelW: CGFloat = 382

    /// 低于此宽度时 .dual 自动改纵向排列
    static let dualCollapseW: CGFloat = 660

    // MARK: - 字体

    static let title = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 13)
    static let small = Font.system(size: 11.5)
    static let sectionHead = Font.system(size: 11.5, weight: .semibold)
    static let sidebarSection = Font.system(size: 12.5, weight: .semibold)
    static let mono = Font.system(size: 12.5, design: .monospaced)
    static let monoLarge = Font.system(size: 16, design: .monospaced)
    static let keycap = Font.system(size: 10.5, design: .monospaced)

    static let nsMono = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)

    // MARK: - 层次色

    /// 窗口壳 / 工具栏
    static let windowBG = dyn(dark: 0x17181D, light: 0xFFFFFF)
    /// 工作区灰底（卡片浮于其上）
    static let contentBG = dyn(dark: 0x121318, light: 0xF1F1F4)
    /// 卡片
    static let cardBG = dyn(dark: 0x1E1F26, light: 0xFFFFFF)
    /// 卡片 hover / 行高亮
    static let cardHoverBG = dyn(dark: 0x25262E, light: 0xFAFAFC)
    /// 输入凹槽（比卡片深一层，macOS 表达「可编辑区域」的方式）
    static let sunkenBG = dyn(dark: 0x131419, light: 0xF7F7F9)

    // MARK: - 语义色（读系统，不写死）

    static let accent = Color.accentColor
    static let separator = Color(nsColor: .separatorColor)
    static let label = Color(nsColor: .labelColor)
    static let secondaryLabel = Color(nsColor: .secondaryLabelColor)
    static let tertiaryLabel = Color(nsColor: .tertiaryLabelColor)

    static let ok = Color(nsColor: .systemGreen)
    static let error = Color(nsColor: .systemRed)
    static let warning = Color(nsColor: .systemOrange)

    static let hover = Color.primary.opacity(0.055)
    static let keycapBG = Color.primary.opacity(0.07)
    static let keycapBorder = Color.primary.opacity(0.1)

    // MARK: - 阴影与描边

    static let cardShadowColor = Color.black.opacity(0.16)
    static let cardShadowRadius: CGFloat = 1.5
    static let cardShadowY: CGFloat = 1

    /// accent 的 2 度微渐变 —— 纯色平涂在 macOS 上显廉价
    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.92), Color.accentColor],
            startPoint: .top, endPoint: .bottom
        )
    }

    // MARK: - 动效（≤160ms，只服务状态切换）

    static let hoverAnim = Animation.easeOut(duration: 0.12)
    static let selectAnim = Animation.easeOut(duration: 0.16)

    // MARK: - Helper

    /// 按外观切换的静态色。系统语义色没有合适映射时才用它。
    private static func dyn(dark: UInt32, light: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - 卡片样式

extension View {
    /// 浮起卡片：圆角 + 描边 + 极淡投影。顶部 inset 高光交给 .cardHighlight()。
    func cardSurface(radius: CGFloat = Tokens.cardRadius) -> some View {
        self
            .background(Tokens.cardBG, in: .rect(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Tokens.separator, lineWidth: 0.5)
            )
            .shadow(color: Tokens.cardShadowColor,
                    radius: Tokens.cardShadowRadius, y: Tokens.cardShadowY)
    }

    /// 凹槽：比卡片深一层 + inset 描边
    func sunkenSurface(radius: CGFloat = 10) -> some View {
        self
            .background(Tokens.sunkenBG, in: .rect(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Tokens.separator, lineWidth: 0.5)
            )
    }
}
