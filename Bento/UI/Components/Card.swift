import SwiftUI

// MARK: - 卡片

/// 浮起在灰底上的内容卡片。头部可选（小圆点 + 标题 + 右侧 meta）。
/// 卡片**整体**获得焦点环，里面的输入控件不再自己描边——少一层框线。
struct Card<Content: View>: View {
    var title: String? = nil
    var dot: Color? = nil
    var meta: String? = nil
    var focused: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if title != nil || meta != nil {
                HStack(spacing: 8) {
                    if let dot {
                        Circle().fill(dot).frame(width: 6, height: 6)
                    }
                    if let title {
                        Text(title)
                            .font(Tokens.sectionHead)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if let meta {
                        Text(meta)
                            .font(Tokens.small)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, Tokens.padCard)
                .frame(height: Tokens.cardHeadH)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.cardBG, in: .rect(cornerRadius: Tokens.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
                .strokeBorder(focused ? Tokens.accent : Tokens.separator,
                              lineWidth: focused ? 1 : 0.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
                .strokeBorder(Tokens.accent.opacity(focused ? 0.22 : 0), lineWidth: 3.5)
                .blur(radius: 0.5)
        )
        .shadow(color: Tokens.cardShadowColor,
                radius: Tokens.cardShadowRadius, y: Tokens.cardShadowY)
        .animation(Tokens.selectAnim, value: focused)
    }
}

/// 卡片底部操作栏，顶部一条 0.5pt 分隔。
struct CardFooter<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 6) {
            content()
        }
        .padding(.horizontal, 10)
        .frame(height: Tokens.cardFootH)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(Tokens.separator).frame(height: 0.5)
        }
    }
}

// MARK: - 选项行

/// 工具顶部的选项条，本身也是一张卡片。
struct OptionBar<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 14) {
            content()
        }
        .padding(.horizontal, Tokens.padCard)
        .frame(height: Tokens.optionBarH)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.cardBG, in: .rect(cornerRadius: Tokens.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
                .strokeBorder(Tokens.separator, lineWidth: 0.5)
        )
        .shadow(color: Tokens.cardShadowColor,
                radius: Tokens.cardShadowRadius, y: Tokens.cardShadowY)
    }
}

/// 选项条上的小标签
struct OptionLabel: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
    }
}

// MARK: - 结果行（form / canvas 模板复用）

/// 一入多出的输出行：行高 36，hover 才出复制按钮。
struct ResultRow: View {
    let key: String
    let value: String
    var keyWidth: CGFloat = 104

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            Text(key)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: keyWidth, alignment: .leading)
            Text(value)
                .font(Tokens.mono)
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            CopyButton(value: value)
                .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, Tokens.padCard)
        .frame(height: Tokens.rowH)
        .background(hovering ? Tokens.cardHoverBG : Color.clear)
        .overlay(alignment: .top) {
            Rectangle().fill(Tokens.separator).frame(height: 0.5)
        }
        .onHover { hovering = $0 }
        .animation(Tokens.hoverAnim, value: hovering)
    }
}

/// 一组结果行（自动去掉第一行的顶部分隔线）
struct ResultRows: View {
    let rows: [(String, String)]
    var keyWidth: CGFloat = 104

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    ResultRow(key: row.0, value: row.1, keyWidth: keyWidth)
                        .overlay(alignment: .top) {
                            if index == 0 {
                                Rectangle().fill(Tokens.cardBG).frame(height: 0.5)
                            }
                        }
                }
            }
        }
        .scrollIndicators(.never)
    }
}

// MARK: - 分段控件

struct BentoSegments<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var accent = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { value, label in
                let on = value == selection
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(on ? (accent ? Color.white : Color.primary) : Color.secondary)
                    .padding(.horizontal, 11)
                    .frame(height: 23)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(accent ? AnyShapeStyle(Tokens.accentGradient)
                                             : AnyShapeStyle(Tokens.cardBG))
                                .shadow(color: Tokens.cardShadowColor, radius: 1, y: 0.5)
                        }
                    }
                    .contentShape(.rect)
                    .onTapGesture { selection = value }
            }
        }
        .padding(2)
        .background(Tokens.sunkenBG, in: .rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Tokens.separator, lineWidth: 0.5)
        )
        .animation(Tokens.hoverAnim, value: selection)
    }
}

// MARK: - 勾选

struct BentoCheck: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isOn ? AnyShapeStyle(Tokens.accentGradient) : AnyShapeStyle(Tokens.sunkenBG))
                .frame(width: 14, height: 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(isOn ? Color.clear : Tokens.separator, lineWidth: 0.5)
                )
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .opacity(isOn ? 1 : 0)
                )
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(isOn ? Color.primary : Color.secondary)
        }
        .contentShape(.rect)
        .onTapGesture { isOn.toggle() }
        .animation(Tokens.hoverAnim, value: isOn)
    }
}
