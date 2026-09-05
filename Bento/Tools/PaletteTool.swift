import SwiftUI

struct PaletteTool: ToolView {
    static let meta = ToolMeta(
        id: "palette", name: "调色板生成", category: .style, layout: .canvas,
        symbol: "swatchpalette",
        aliases: ["palette", "scale", "shades", "tsb", "tiaoseban"]
    )

    enum Output: Hashable, CaseIterable {
        case swiftui, css, tailwind, json

        var label: String {
            switch self {
            case .swiftui:  return "SwiftUI"
            case .css:      return "CSS 变量"
            case .tailwind: return "Tailwind"
            case .json:     return "JSON"
            }
        }
    }

    @State private var baseHex = "#4A90D9"
    @State private var style: ColorMath.PaletteStyle = .tailwind
    @State private var output: Output = .swiftui
    @State private var name = "brand"

    init() {}

    var body: some View {
        StackLayout(status: status) {
            OptionLabel(text: "风格")
            BentoSegments(options: ColorMath.PaletteStyle.allCases.map { ($0, $0.label) },
                          selection: $style)
            OptionLabel(text: "命名")
            TextField("brand", text: $name)
                .textFieldStyle(.plain)
                .font(Tokens.mono)
                .padding(.horizontal, 9)
                .frame(width: 100, height: 26)
                .sunkenSurface(radius: 6)
            Spacer()
        } content: {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 26) {
                        ColorField(label: "基色（作为 500 档锚点）", hex: $baseHex)
                        Spacer()
                        if let c = base {
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("最接近 Tailwind").font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                let n = ColorMath.nearestTailwind(c)
                                Text("\(n.name)  Δ\(n.distance)")
                                    .font(.system(size: 13, design: .monospaced))
                            }
                        }
                    }
                    if !stops.isEmpty {
                        SwatchStrip(items: stops)
                    }
                }
                .padding(Tokens.padCard)
            }
            .fixedSize(horizontal: false, vertical: true)

            if let c = base {
                Card(title: "配色关系", dot: ToolCategory.style.tint, meta: "点色卡复制") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(ColorMath.harmony(c), id: \.name) { h in
                            HStack(spacing: 12) {
                                Text(h.name)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 62, alignment: .leading)
                                SwatchStrip(
                                    items: h.colors.map { ($0.hex, $0) },
                                    height: 26, showNames: false
                                )
                                .frame(maxWidth: 260)
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, Tokens.padCard)
                    .padding(.bottom, Tokens.padCard)
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            Card(title: "代码", dot: ToolCategory.image.tint, meta: output.label) {
                HStack(spacing: 6) {
                    BentoSegments(options: Output.allCases.map { ($0, $0.label) },
                                  selection: $output)
                    Spacer()
                    CopyButton(value: code, compact: false)
                }
                .padding(.horizontal, Tokens.padCard)
                .padding(.bottom, 8)
                CodeArea(text: .constant(code), isEditable: false)
            }
        }
    }

    // MARK: -

    private var base: ColorMath.RGB? { ColorMath.parse(baseHex) }

    private var stops: [(name: String, color: ColorMath.RGB)] {
        base.map { ColorMath.palette($0, style: style) } ?? []
    }

    private var code: String {
        guard !stops.isEmpty else { return "" }
        let key = name.isEmpty ? "brand" : name
        switch output {
        case .swiftui:
            var lines = ["extension Color {", "    enum \(key.uppercasedFirst()) {"]
            for s in stops {
                let (r, g, b) = s.color.bytes
                lines.append(String(format: "        static let s%@ = Color(.sRGB, red: %.3f, green: %.3f, blue: %.3f, opacity: 1)  // %@",
                                    s.name, Double(r) / 255, Double(g) / 255, Double(b) / 255, s.color.hex))
            }
            lines.append("    }"); lines.append("}")
            return lines.joined(separator: "\n")

        case .css:
            return ":root {\n" + stops.map { "  --\(key)-\($0.name): \($0.color.hex.lowercased());" }
                .joined(separator: "\n") + "\n}"

        case .tailwind:
            return "// tailwind.config.js\ncolors: {\n  \(key): {\n"
                + stops.map { "    \($0.name): '\($0.color.hex.lowercased())'," }.joined(separator: "\n")
                + "\n  },\n}"

        case .json:
            return "{\n  \"\(key)\": {\n"
                + stops.map { "    \"\($0.name)\": \"\($0.color.hex.lowercased())\"" }
                    .joined(separator: ",\n")
                + "\n  }\n}"
        }
    }

    private var status: StatusLine {
        guard let c = base else {
            return StatusLine(level: .error, text: "基色无法解析",
                              trailing: style.label, trailingKey: "⌄")
        }
        // 顺带提醒哪几档能安全地放白字，这是实际用色阶时最常问的问题
        let onWhite = stops.filter { ColorMath.contrast($0.color, ColorMath.RGB(r: 1, g: 1, b: 1)) >= 4.5 }
        let hsl = ColorMath.toHSL(c)
        return StatusLine(
            level: .ok,
            text: "\(stops.count) 档 · 色相 \(Int(hsl.h))° 饱和 \(Int(hsl.s * 100))% · "
                + "\(onWhite.first?.name ?? "无") 及以上可在白底放正文",
            trailing: style.label, trailingKey: "⌄"
        )
    }
}
