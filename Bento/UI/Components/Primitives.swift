import SwiftUI

// MARK: - 键帽

/// 快捷键做成可按的物件，不是灰字。
struct Keycap: View {
    let text: String
    var dimmed = false

    var body: some View {
        Text(text)
            .font(Tokens.keycap)
            .foregroundStyle(dimmed ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 4.5)
            .frame(minWidth: 17, minHeight: 17)
            .background(Tokens.keycapBG, in: .rect(cornerRadius: 4.5))
            .overlay(
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .strokeBorder(Tokens.keycapBorder, lineWidth: 0.5)
            )
            .fixedSize()
    }
}

// MARK: - 分类图标方块

/// 设计感的主要来源：色只上图标和它的淡底，不做大色块。
struct CategoryIcon: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = Tokens.iconSmall
    var selected = false

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(selected ? Color.white.opacity(0.22) : tint.opacity(0.17))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.54, weight: .medium))
                    .foregroundStyle(selected ? Color.white : tint)
            )
    }
}

// MARK: - 状态行

struct StatusLine: View {
    enum Level {
        case idle, ok, error, warning

        var color: Color {
            switch self {
            case .idle:    return Tokens.tertiaryLabel
            case .ok:      return Tokens.ok
            case .error:   return Tokens.error
            case .warning: return Tokens.warning
            }
        }
        var glows: Bool { self != .idle }
    }

    var level: Level = .idle
    var text: String = ""
    var trailing: String? = nil
    var trailingKey: String? = nil

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(level.color)
                .frame(width: 7, height: 7)
                .shadow(color: level.glows ? level.color.opacity(0.75) : .clear, radius: 3)
            Text(text)
                .font(Tokens.small)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing).font(Tokens.small).foregroundStyle(.secondary)
            }
            if let trailingKey {
                Keycap(text: trailingKey)
            }
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 18)
    }
}

// MARK: - 复制按钮的通用反馈

/// 复制成功不弹 toast：图标变 checkmark 约 0.9s。
struct CopyButton: View {
    let value: String
    var compact = true

    @State private var copied = false

    var body: some View {
        if compact {
            Button(action: copy) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
                    .frame(width: 24, height: 24)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(copied ? Tokens.accent : Color.secondary)
            .animation(Tokens.hoverAnim, value: copied)
        } else {
            Button(action: copy) {
                HStack(spacing: 5) {
                    Text(copied ? "已复制" : "复制")
                    Keycap(text: "⌘⌥C")
                }
            }
            .bentoButton()
            .animation(Tokens.hoverAnim, value: copied)
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { copied = false }
    }
}

// MARK: - 按钮样式

/// macOS 语义按钮：26pt 高、圆角 7、卡片底 + 描边，按下轻微缩放。
struct BentoButtonStyle: ButtonStyle {
    var prominent = false
    var plain = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(prominent ? AnyShapeStyle(Color.white)
                                       : AnyShapeStyle(plain ? Color.secondary : Color.primary))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background {
                if prominent {
                    RoundedRectangle(cornerRadius: Tokens.ctlRadius, style: .continuous)
                        .fill(Tokens.accentGradient)
                } else if plain {
                    RoundedRectangle(cornerRadius: Tokens.ctlRadius, style: .continuous)
                        .fill(configuration.isPressed ? Tokens.hover : Color.clear)
                } else {
                    RoundedRectangle(cornerRadius: Tokens.ctlRadius, style: .continuous)
                        .fill(Tokens.cardBG)
                        .overlay(
                            RoundedRectangle(cornerRadius: Tokens.ctlRadius, style: .continuous)
                                .strokeBorder(Tokens.separator, lineWidth: 0.5)
                        )
                        .shadow(color: Tokens.cardShadowColor, radius: 1, y: 0.5)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Tokens.hoverAnim, value: configuration.isPressed)
    }
}

/// 三元里混用 `Color` 和 `.secondary` 这类 ShapeStyle 会编译不过
/// （两边类型不一致），包一层省得每次手写 AnyShapeStyle。
func styleIf(_ condition: Bool, _ whenTrue: some ShapeStyle,
             _ whenFalse: some ShapeStyle) -> AnyShapeStyle {
    condition ? AnyShapeStyle(whenTrue) : AnyShapeStyle(whenFalse)
}

extension View {
    func bentoButton(prominent: Bool = false, plain: Bool = false) -> some View {
        buttonStyle(BentoButtonStyle(prominent: prominent, plain: plain))
    }
}
