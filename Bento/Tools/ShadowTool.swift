import SwiftUI

struct ShadowTool: ToolView {
    static let meta = ToolMeta(
        id: "shadow", name: "阴影生成", category: .style, layout: .canvas,
        symbol: "square.3.layers.3d.top.filled",
        aliases: ["shadow", "boxshadow", "yy", "yinying"]
    )

    struct Layer: Identifiable {
        let id = UUID()
        var x: Double = 0
        var y: Double = 2
        var blur: Double = 8
        var spread: Double = 0
        var hex: String = "#000000"
        var opacity: Double = 0.18
        var inset = false
    }

    /// 常见的几种阴影，直接对应设计系统里的 elevation 档位
    private static let presets: [(String, [Layer])] = [
        ("卡片", [Layer(x: 0, y: 1, blur: 3, spread: 0, opacity: 0.10),
                 Layer(x: 0, y: 1, blur: 2, spread: -1, opacity: 0.06)]),
        ("浮起", [Layer(x: 0, y: 4, blur: 12, spread: -2, opacity: 0.14),
                 Layer(x: 0, y: 2, blur: 4, spread: -2, opacity: 0.08)]),
        ("弹窗", [Layer(x: 0, y: 24, blur: 48, spread: -12, opacity: 0.35)]),
        ("内凹", [Layer(x: 0, y: 1, blur: 2, spread: 0, opacity: 0.20, inset: true)]),
    ]

    @State private var layers: [Layer] = ShadowTool.presets[1].1
    @State private var bgHex = "#F1F1F4"
    @State private var boxHex = "#FFFFFF"
    @State private var radius: Double = 12

    init() {}

    var body: some View {
        StackLayout(status: status) {
            OptionLabel(text: "预设")
            ForEach(Self.presets, id: \.0) { name, l in
                Button(name) { layers = l }.bentoButton()
            }
            Spacer()
            Button {
                layers.append(Layer())
            } label: {
                HStack(spacing: 4) { Image(systemName: "plus"); Text("加一层") }
            }
            .bentoButton(prominent: true)
        } content: {
            Card {
                HStack(alignment: .top, spacing: 20) {
                    preview
                    controls
                }
                .padding(Tokens.padCard)
            }
            .fixedSize(horizontal: false, vertical: true)

            Card(title: "代码输出", dot: ToolCategory.style.tint, meta: "3 种 · 逐行复制") {
                ResultRows(rows: codeRows, keyWidth: 118)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: - 预览

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(color(boxHex) ?? .white)
                .frame(width: 130, height: 90)
                .modifier(ShadowStack(layers: layers.filter { !$0.inset }))
                .overlay(insetHint)
        }
        .frame(width: 260, height: 200)
        .background(color(bgHex) ?? Tokens.contentBG)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Tokens.separator, lineWidth: 0.5)
        )
    }

    /// SwiftUI 没有 inset shadow，用内描边近似示意，并在状态栏说明
    @ViewBuilder
    private var insetHint: some View {
        if layers.contains(where: \.inset) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.black.opacity(0.16), lineWidth: 2)
                .blur(radius: 1.5)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                ColorField(label: "卡片", hex: $boxHex, size: 30)
                ColorField(label: "背景", hex: $bgHex, size: 30)
            }
            HStack(spacing: 8) {
                Text("圆角").font(.system(size: 12)).foregroundStyle(.secondary)
                Slider(value: $radius, in: 0...40, step: 1)
                Text("\(Int(radius))").font(Tokens.mono).monospacedDigit()
                    .frame(width: 26, alignment: .trailing)
            }
            Divider()
            ScrollView {
                VStack(spacing: 10) {
                    ForEach($layers) { $layer in
                        LayerEditor(layer: $layer) {
                            layers.removeAll { $0.id == layer.id }
                        }
                    }
                }
            }
            .frame(maxHeight: 150)
            .scrollIndicators(.never)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 输出

    private var codeRows: [(String, String)] {
        [("CSS", cssValue),
         ("SwiftUI", swiftUIValue),
         ("AppKit", appKitValue)]
    }

    private var cssValue: String {
        guard !layers.isEmpty else { return "box-shadow: none;" }
        let parts = layers.map { l -> String in
            let c = ColorMath.parse(l.hex) ?? ColorMath.RGB(r: 0, g: 0, b: 0)
            let (r, g, b) = c.bytes
            return "\(l.inset ? "inset " : "")\(fmt(l.x))px \(fmt(l.y))px \(fmt(l.blur))px "
                 + "\(fmt(l.spread))px rgba(\(r), \(g), \(b), \(String(format: "%.2f", l.opacity)))"
        }
        return "box-shadow: " + parts.joined(separator: ", ") + ";"
    }

    private var swiftUIValue: String {
        let outer = layers.filter { !$0.inset }
        guard !outer.isEmpty else { return "// 没有外阴影" }
        // SwiftUI 的 shadow radius 约等于 CSS blur 的一半
        return outer.map { l -> String in
            let c = ColorMath.parse(l.hex) ?? ColorMath.RGB(r: 0, g: 0, b: 0)
            return String(format: ".shadow(color: Color(.sRGB, red: %.2f, green: %.2f, blue: %.2f, opacity: %.2f), radius: %g, x: %g, y: %g)",
                          c.r, c.g, c.b, l.opacity, l.blur / 2, l.x, l.y)
        }.joined(separator: "\n")
    }

    private var appKitValue: String {
        guard let l = layers.first(where: { !$0.inset }) else { return "// 没有外阴影" }
        let c = ColorMath.parse(l.hex) ?? ColorMath.RGB(r: 0, g: 0, b: 0)
        return String(format: "layer.shadowColor = NSColor(srgbRed: %.2f, green: %.2f, blue: %.2f, alpha: 1).cgColor; layer.shadowOpacity = %.2f; layer.shadowRadius = %g; layer.shadowOffset = CGSize(width: %g, height: %g)",
                      c.r, c.g, c.b, l.opacity, l.blur / 2, l.x, -l.y)
    }

    private func fmt(_ v: Double) -> String { String(format: "%g", v) }

    private func color(_ hex: String) -> Color? {
        ColorMath.parse(hex).map { Color(.sRGB, red: $0.r, green: $0.g, blue: $0.b, opacity: 1) }
    }

    private var status: StatusLine {
        if layers.isEmpty {
            return StatusLine(level: .idle, text: "没有阴影层", trailing: "box-shadow", trailingKey: "⌄")
        }
        if layers.contains(where: \.inset) {
            return StatusLine(level: .warning,
                              text: "\(layers.count) 层 · inset 只有 CSS 支持，SwiftUI / AppKit 需用内描边或渐变模拟",
                              trailing: "box-shadow", trailingKey: "⌄")
        }
        return StatusLine(level: .ok,
                          text: "\(layers.count) 层 · SwiftUI 的 radius ≈ CSS blur ÷ 2，已自动换算",
                          trailing: "box-shadow", trailingKey: "⌄")
    }
}

// MARK: - 子视图

/// 多层阴影靠嵌套 modifier 叠加
private struct ShadowStack: ViewModifier {
    let layers: [ShadowTool.Layer]

    func body(content: Content) -> some View {
        layers.reduce(AnyView(content)) { view, l in
            let c = ColorMath.parse(l.hex) ?? ColorMath.RGB(r: 0, g: 0, b: 0)
            return AnyView(view.shadow(
                color: Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: l.opacity),
                radius: l.blur / 2, x: l.x, y: l.y
            ))
        }
    }
}

private struct LayerEditor: View {
    @Binding var layer: ShadowTool.Layer
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                ColorField(label: "", hex: $layer.hex, size: 20, showSampler: false)
                    .frame(width: 150)
                BentoCheck(label: "inset", isOn: $layer.inset)
                Spacer()
                Button { onDelete() } label: { Image(systemName: "trash") }
                    .bentoButton(plain: true)
            }
            HStack(spacing: 10) {
                slider("X", $layer.x, -40...40)
                slider("Y", $layer.y, -40...40)
            }
            HStack(spacing: 10) {
                slider("模糊", $layer.blur, 0...80)
                slider("扩散", $layer.spread, -40...40)
            }
            slider("不透明", $layer.opacity, 0...1, decimals: 2)
        }
        .padding(9)
        .background(Tokens.sunkenBG, in: .rect(cornerRadius: 8))
    }

    private func slider(_ label: String, _ value: Binding<Double>,
                        _ range: ClosedRange<Double>, decimals: Int = 0) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
            Slider(value: value, in: range)
            Text(decimals == 0 ? "\(Int(value.wrappedValue))"
                               : String(format: "%.2f", value.wrappedValue))
                .font(.system(size: 11, design: .monospaced))
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)
        }
    }
}
