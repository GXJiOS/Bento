import SwiftUI

// MARK: - 基础骨架

/// 所有工具的外壳：灰底 + 选项条 + 内容 + 状态行。
/// 工具**不写自己的页面骨架**，只填这三块。
struct ToolScaffold<Options: View, Content: View>: View {
    var status: StatusLine
    @ViewBuilder var options: () -> Options
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: Tokens.gapCard) {
            OptionBar { options() }
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            status
        }
        .padding(Tokens.padContent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.contentBG)
    }
}

// MARK: - ① dual

/// 左右双栏 · 约 24 个工具。
/// 窄于 660pt 自动改纵向排列，卡片本身不重做。
struct DualLayout<Options: View, Input: View, Output: View>: View {
    var status: StatusLine
    /// 可逆工具传这个，分隔间隙里会出现 ⇅
    var onSwap: (() -> Void)? = nil
    @ViewBuilder var options: () -> Options
    @ViewBuilder var input: () -> Input
    @ViewBuilder var output: () -> Output

    var body: some View {
        ToolScaffold(status: status) {
            options()
        } content: {
            GeometryReader { geo in
                let narrow = geo.size.width < Tokens.dualCollapseW
                ZStack {
                    if narrow {
                        VStack(spacing: Tokens.gapCard) { input(); output() }
                    } else {
                        HStack(spacing: Tokens.gapCard) { input(); output() }
                    }
                    if let onSwap {
                        SwapButton(action: onSwap)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }
}

struct SwapButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovering ? Tokens.accent : Color.secondary)
                .frame(width: 30, height: 30)
                .background(Tokens.cardBG, in: .circle)
                .overlay(Circle().strokeBorder(Tokens.separator, lineWidth: 0.5))
                .shadow(color: Tokens.cardShadowColor, radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.1 : 1)
        .onHover { hovering = $0 }
        .animation(Tokens.hoverAnim, value: hovering)
        .help("交换输入输出 ⌘⇧S")
    }
}

// MARK: - ② stacked / ③ form / ④ canvas

/// 纵向堆叠若干卡片。三个模板共用同一套排布，差别只在工具怎么填：
///   .stacked — 表达式卡 / 文本+高亮卡 / 结果表卡
///   .form    — 输入卡 / 结果行卡
///   .canvas  — 画布卡 / 代码输出卡
struct StackLayout<Options: View, Content: View>: View {
    var status: StatusLine
    @ViewBuilder var options: () -> Options
    @ViewBuilder var content: () -> Content

    var body: some View {
        ToolScaffold(status: status) {
            options()
        } content: {
            VStack(spacing: Tokens.gapCard) {
                content()
            }
        }
    }
}

// MARK: - 双输入对比

/// Diff 类工具的骨架：两个并排输入卡 + 下方结果卡。
/// 和 `.dual` 的区别是「两个都是输入」，不是输入→输出。
struct CompareLayout<Options: View, Result: View>: View {
    var status: StatusLine
    @Binding var left: String
    @Binding var right: String
    var leftTitle = "原始"
    var rightTitle = "对比"
    var inputHeight: CGFloat = 150
    var leftMeta: String? = nil
    var rightMeta: String? = nil
    @ViewBuilder var options: () -> Options
    @ViewBuilder var result: () -> Result

    var body: some View {
        StackLayout(status: status) {
            options()
        } content: {
            HStack(spacing: Tokens.gapCard) {
                Card(title: leftTitle, dot: Tokens.error, meta: leftMeta) {
                    CodeArea(text: $left, placeholder: "粘贴原始内容…")
                }
                Card(title: rightTitle, dot: Tokens.ok, meta: rightMeta) {
                    CodeArea(text: $right, placeholder: "粘贴要对比的内容…")
                }
            }
            .frame(height: inputHeight)

            result()
        }
    }
}

// MARK: - 空状态

struct EmptyToolView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text("按 ⌘K 打开命令面板")
                .font(Tokens.body)
                .foregroundStyle(.secondary)
            Text("或从左侧选择一个工具")
                .font(Tokens.small)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.contentBG)
    }
}
