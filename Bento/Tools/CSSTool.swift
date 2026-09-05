import SwiftUI

struct CSSTool: ToolView {
    static let meta = ToolMeta(
        id: "css2swiftui", name: "CSS → SwiftUI", category: .style, layout: .dual,
        symbol: "arrow.right.doc.on.clipboard",
        aliases: ["css", "swiftui", "convert", "css2s"]
    )

    private static let sample = """
        display: flex;
        flex-direction: column;
        gap: 12px;
        color: #1F2937;
        background-color: rgba(255, 255, 255, 0.9);
        font-size: 0.875rem;
        font-weight: 600;
        line-height: 1.5;
        padding: 12px 16px;
        border-radius: 12px;
        border: 1px solid #E5E7EB;
        box-shadow: 0 4px 12px rgba(0, 0, 0, 0.08);
        """

    @State private var input = CSSTool.sample
    @State private var showNotes = true

    init() {}

    var body: some View {
        ConverterView(
            input: $input,
            output: output,
            category: .style,
            placeholder: "粘贴 CSS 声明，或整段 .foo { … }",
            okText: okText,
            trailing: "\(decls.count) 条声明",
            memoryKey: Self.meta.id
        ) {
            OptionLabel(text: "输出")
            BentoCheck(label: "带提示注释", isOn: $showNotes)
            Spacer()
            Text("修饰符按「文本 → 布局 → 装饰 → 效果」排序")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
                .help("SwiftUI 里顺序影响渲染结果，比如 .background 必须在 .padding 之后")
        }
    }

    private var decls: [CSSConverter.Declaration] {
        CSSConverter.parse(input)
    }

    private var result: CSSConverter.Result {
        CSSConverter.toSwiftUI(decls)
    }

    private var output: String {
        guard !input.trimmed.isEmpty else { return "" }
        let r = result
        var lines: [String] = []

        if showNotes, !r.notes.isEmpty {
            lines += r.notes.map { "// \($0)" }
            lines.append("")
        }
        lines.append("SomeView()")
        lines += r.modifiers.map { "    \($0)" }

        if showNotes, !r.unsupported.isEmpty {
            lines.append("")
            lines.append("// ── SwiftUI 没有直接对应，需要手工处理 ──")
            lines += r.unsupported.map { "// \($0.property): \($0.value);" }
        }
        return lines.joined(separator: "\n")
    }

    private var okText: String {
        let r = result
        var s = "已转换 \(r.modifiers.count) 个修饰符"
        if !r.unsupported.isEmpty { s += " · \(r.unsupported.count) 条未支持" }
        return s
    }
}
