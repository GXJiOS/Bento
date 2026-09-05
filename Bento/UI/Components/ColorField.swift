import SwiftUI
import AppKit

/// 色块 + HEX 输入 + 系统吸管。样式与调色板类工具共用。
struct ColorField: View {
    let label: String
    @Binding var hex: String
    var size: CGFloat = 52
    var showSampler = true

    private var color: Color {
        ColorMath.parse(hex).map {
            Color(.sRGB, red: $0.r, green: $0.g, blue: $0.b, opacity: $0.a)
        } ?? Color.gray.opacity(0.3)
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .fill(color)
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                        .strokeBorder(.black.opacity(0.18), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.14), radius: 3, y: 1.5)

            VStack(alignment: .leading, spacing: 7) {
                Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    TextField("#RRGGBB", text: $hex)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13.5, design: .monospaced))
                        .padding(.horizontal, 9)
                        .frame(width: 116, height: 28)
                        .sunkenSurface(radius: 7)
                    if showSampler {
                        Button {
                            NSColorSampler().show { picked in
                                guard let picked else { return }
                                let c = picked.usingColorSpace(.sRGB) ?? picked
                                hex = String(format: "#%02X%02X%02X",
                                             Int((c.redComponent * 255).rounded()),
                                             Int((c.greenComponent * 255).rounded()),
                                             Int((c.blueComponent * 255).rounded()))
                            }
                        } label: {
                            Image(systemName: "eyedropper")
                        }
                        .bentoButton()
                        .help("屏幕取色 — NSColorSampler")
                    }
                }
            }
        }
    }
}

/// 一排色卡，点一下复制。
/// 单元格拆成独立视图 —— 整条链写在一个 body 里会让类型检查器超时。
struct SwatchStrip: View {
    let items: [(name: String, color: ColorMath.RGB)]
    var height: CGFloat = 58
    var showNames = true

    @State private var copiedIndex: Int?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                SwatchCell(name: item.name, color: item.color,
                           height: height, showName: showNames, copied: copiedIndex == i)
                    .onTapGesture { copy(item.color, at: i) }
            }
        }
        .animation(Tokens.hoverAnim, value: copiedIndex)
    }

    private func copy(_ color: ColorMath.RGB, at index: Int) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(color.hex, forType: .string)
        copiedIndex = index
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { copiedIndex = nil }
    }
}

private struct SwatchCell: View {
    let name: String
    let color: ColorMath.RGB
    let height: CGFloat
    let showName: Bool
    let copied: Bool

    private var fill: Color {
        Color(.sRGB, red: color.r, green: color.g, blue: color.b, opacity: 1)
    }
    /// 勾选标记要在浅色卡上用黑、深色卡上用白，否则看不见
    private var checkColor: Color {
        ColorMath.luminance(color) > 0.5 ? .black : .white
    }

    var body: some View {
        VStack(spacing: 4) {
            chip
            if showName {
                Text(name).font(.system(size: 10)).foregroundStyle(.secondary)
                Text(color.hex).font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(.rect)
        .help("点击复制 \(color.hex)")
    }

    private var chip: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(fill)
            .frame(height: height)
            .overlay(border)
            .overlay(check)
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(.black.opacity(0.12), lineWidth: 0.5)
    }

    private var check: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(checkColor)
            .opacity(copied ? 1 : 0)
    }
}
