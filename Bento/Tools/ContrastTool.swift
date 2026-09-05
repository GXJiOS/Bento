import SwiftUI

struct ContrastTool: ToolView {
    static let meta = ToolMeta(
        id: "contrast", name: "对比度检查", category: .style, layout: .form,
        symbol: "circle.lefthalf.filled",
        aliases: ["contrast", "wcag", "a11y", "dbd", "duibidu"]
    )

    @State private var fgHex = "#4A90D9"
    @State private var bgHex = "#FFFFFF"
    @State private var largeText = false

    init() {}

    var body: some View {
        StackLayout(status: status) {
            OptionLabel(text: "文本")
            BentoSegments(options: [(false, "正常 (< 18pt)"), (true, "大字 (≥ 18pt / 14pt 粗)")],
                          selection: $largeText)
            Spacer()
            Button("交换前后景") { swap(&fgHex, &bgHex) }.bentoButton()
        } content: {
            Card {
                HStack(spacing: 26) {
                    ColorField(label: "前景 / 文字", hex: $fgHex)
                    ColorField(label: "背景", hex: $bgHex)
                    Spacer()
                    ratioBadge
                }
                .padding(Tokens.padCard)
            }
            .fixedSize(horizontal: false, vertical: true)

            Card(title: "实际效果", dot: ToolCategory.style.tint, meta: "所见即所得") {
                preview
            }
            .fixedSize(horizontal: false, vertical: true)

            Card(title: "判定与建议", dot: ToolCategory.image.tint, meta: "WCAG 2.1") {
                ResultRows(rows: rows, keyWidth: 150)
                    .frame(maxHeight: .infinity)
                if let fixed = suggestion {
                    suggestionBar(fixed)
                }
            }
        }
    }

    // MARK: - 视图片段

    private var ratioBadge: some View {
        VStack(spacing: 4) {
            Text(String(format: "%.2f:1", ratio))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(level.rawValue)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(level.passes ? Tokens.ok : Tokens.error)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background((level.passes ? Tokens.ok : Tokens.error).opacity(0.16),
                            in: .rect(cornerRadius: 6))
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("正常正文 14pt — The quick brown fox 敏捷的棕色狐狸")
                .font(.system(size: 14))
            Text("大字标题 20pt 粗")
                .font(.system(size: 20, weight: .semibold))
            Text("小字说明 11pt — 12 行 · 348 字符 · 1.2 ms")
                .font(.system(size: 11))
        }
        .foregroundStyle(fg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(bg)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Tokens.separator, lineWidth: 0.5)
        )
        .clipShape(.rect(cornerRadius: 8))
        .padding(.horizontal, Tokens.padCard)
        .padding(.bottom, Tokens.padCard)
    }

    private func suggestionBar(_ fixed: ColorMath.RGB) -> some View {
        HStack(spacing: 12) {
            Text("建议前景")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(.sRGB, red: fixed.r, green: fixed.g, blue: fixed.b, opacity: 1))
                .frame(width: 22, height: 22)
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(.black.opacity(0.15), lineWidth: 0.5))
            Text(fixed.hex).font(Tokens.mono)
            Text(String(format: "→ %.2f:1", ColorMath.contrast(fixed, bgRGB ?? fixed)))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            Button("采用") { fgHex = fixed.hex }.bentoButton(prominent: true)
        }
        .padding(.horizontal, Tokens.padCard)
        .frame(height: 46)
        .overlay(alignment: .top) { Rectangle().fill(Tokens.separator).frame(height: 0.5) }
    }

    // MARK: - 计算

    private var fgRGB: ColorMath.RGB? { ColorMath.parse(fgHex) }
    private var bgRGB: ColorMath.RGB? { ColorMath.parse(bgHex) }

    private var fg: Color {
        fgRGB.map { Color(.sRGB, red: $0.r, green: $0.g, blue: $0.b, opacity: 1) } ?? .primary
    }
    private var bg: Color {
        bgRGB.map { Color(.sRGB, red: $0.r, green: $0.g, blue: $0.b, opacity: 1) } ?? .clear
    }

    private var ratio: Double {
        guard let f = fgRGB, let b = bgRGB else { return 0 }
        return ColorMath.contrast(f, b)
    }

    private var level: ColorMath.WCAGLevel {
        ColorMath.level(ratio, largeText: largeText)
    }

    /// 达不到 AA 时给一个最接近的达标色
    private var suggestion: ColorMath.RGB? {
        guard let f = fgRGB, let b = bgRGB else { return nil }
        let target = largeText ? 3.0 : 4.5
        guard ratio < target else { return nil }
        guard let fixed = ColorMath.adjust(f, on: b, target: target), fixed != f else { return nil }
        return fixed
    }

    private var rows: [(String, String)] {
        guard fgRGB != nil, bgRGB != nil else { return [] }
        func line(_ threshold: Double, _ label: String) -> String {
            let pass = ratio >= threshold
            return "\(pass ? "✓ 通过" : "✕ 未通过")    需要 ≥ \(String(format: "%.1f", threshold)):1"
                + (pass ? "" : String(format: "，还差 %.2f", threshold - ratio))
        }
        return [
            ("AA · 正常文本", line(4.5, "AA")),
            ("AA · 大字", line(3.0, "AA大")),
            ("AAA · 正常文本", line(7.0, "AAA")),
            ("AAA · 大字", line(4.5, "AAA大")),
            ("UI 组件 / 图形", line(3.0, "非文本")),
            ("前景相对亮度", String(format: "%.4f", ColorMath.luminance(fgRGB!))),
            ("背景相对亮度", String(format: "%.4f", ColorMath.luminance(bgRGB!))),
        ]
    }

    private var status: StatusLine {
        guard fgRGB != nil else {
            return StatusLine(level: .error, text: "前景色无法解析", trailing: "WCAG 2.1", trailingKey: "⌄")
        }
        guard bgRGB != nil else {
            return StatusLine(level: .error, text: "背景色无法解析", trailing: "WCAG 2.1", trailingKey: "⌄")
        }
        switch level {
        case .aaa:
            return StatusLine(level: .ok, text: "AAA 通过 · 任何场景都够用",
                              trailing: "WCAG 2.1", trailingKey: "⌄")
        case .aa:
            return StatusLine(level: .ok, text: "AA 通过 · 正文可用，AAA 还差 \(String(format: "%.2f", 7 - ratio))",
                              trailing: "WCAG 2.1", trailingKey: "⌄")
        case .aaLarge:
            return StatusLine(level: .warning, text: "只够大字用 · 正文需 ≥ 4.5:1",
                              trailing: "WCAG 2.1", trailingKey: "⌄")
        case .fail:
            return StatusLine(level: .error, text: "不合规 · 需 ≥ \(largeText ? "3.0" : "4.5"):1",
                              trailing: "WCAG 2.1", trailingKey: "⌄")
        }
    }
}
