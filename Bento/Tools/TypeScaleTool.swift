import SwiftUI

struct TypeScaleTool: ToolView {
    static let meta = ToolMeta(
        id: "typescale", name: "字号阶梯", category: .style, layout: .canvas,
        symbol: "textformat.size",
        aliases: ["typescale", "scale", "font", "zhjt", "zihao"]
    )

    /// 模块化比例。名字是排版学里的通用叫法，比记数字直观。
    private static let ratios: [(String, Double)] = [
        ("小二度 1.067", 1.067), ("大二度 1.125", 1.125), ("小三度 1.200", 1.200),
        ("大三度 1.250", 1.250), ("完全四度 1.333", 1.333), ("增四度 1.414", 1.414),
        ("完全五度 1.500", 1.500), ("黄金比 1.618", 1.618),
    ]

    private static let names = ["xs", "sm", "base", "lg", "xl", "2xl", "3xl", "4xl", "5xl"]

    @State private var base: Double = 13
    @State private var ratioIndex = 1
    @State private var rounding = true

    init() {}

    var body: some View {
        StackLayout(status: status) {
            OptionLabel(text: "比例")
            Picker("", selection: $ratioIndex) {
                ForEach(Array(Self.ratios.enumerated()), id: \.offset) { i, r in
                    Text(r.0).tag(i)
                }
            }
            .labelsHidden()
            .frame(width: 160)
            OptionLabel(text: "基准")
            Slider(value: $base, in: 10...20, step: 0.5).frame(width: 130)
            Text("\(fmt(base)) pt").font(Tokens.mono).monospacedDigit().frame(width: 52)
            BentoCheck(label: "取整", isOn: $rounding)
            Spacer()
        } content: {
            Card(title: "预览", dot: ToolCategory.style.tint, meta: "\(steps.count) 档") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(steps.reversed(), id: \.name) { step in
                            HStack(alignment: .firstTextBaseline, spacing: 14) {
                                Text(step.name)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 34, alignment: .trailing)
                                Text("\(fmt(step.size))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 34, alignment: .trailing)
                                Text("敏捷的棕色狐狸 Quick fox")
                                    .font(.system(size: step.size))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.horizontal, Tokens.padCard)
                    .padding(.bottom, Tokens.padCard)
                }
                .scrollIndicators(.never)
            }

            Card(title: "代码", dot: ToolCategory.image.tint, meta: "SwiftUI / CSS / Tailwind") {
                ResultRows(rows: codeRows, keyWidth: 96)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: -

    private var ratio: Double { Self.ratios[ratioIndex].1 }

    private var steps: [(name: String, size: Double)] {
        // base 固定在第 3 档（index 2），往下两档往上六档
        Self.names.enumerated().map { i, name in
            let raw = base * pow(ratio, Double(i - 2))
            return (name, rounding ? (raw * 2).rounded() / 2 : raw)
        }
    }

    private var codeRows: [(String, String)] {
        [
            ("SwiftUI", "enum FontSize {\n" + steps.map {
                "    static let \(swiftName($0.name)): CGFloat = \(fmt($0.size))"
            }.joined(separator: "\n") + "\n}"),
            ("CSS", ":root {\n" + steps.map {
                "  --text-\($0.name): \(fmt($0.size / 16))rem;  /* \(fmt($0.size))px */"
            }.joined(separator: "\n") + "\n}"),
            ("Tailwind", "fontSize: {\n" + steps.map {
                "  '\($0.name)': '\(fmt($0.size / 16))rem',"
            }.joined(separator: "\n") + "\n}"),
        ]
    }

    private func swiftName(_ s: String) -> String {
        // Swift 标识符不能以数字开头：2xl → xl2
        guard let first = s.first, first.isNumber else { return s }
        return String(s.dropFirst()) + String(first)
    }

    private func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    private var status: StatusLine {
        let smallest = steps.first?.size ?? 0
        let level: StatusLine.Level = smallest < 11 ? .warning : .ok
        let hint = smallest < 11
            ? "最小档 \(fmt(smallest))pt 偏小 · macOS 正文建议 ≥ 11pt"
            : "基准 \(fmt(base))pt × \(String(format: "%.3f", ratio)) · 共 \(steps.count) 档"
        return StatusLine(level: level, text: hint,
                          trailing: Self.ratios[ratioIndex].0, trailingKey: "⌄")
    }
}
