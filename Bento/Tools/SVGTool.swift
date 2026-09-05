import SwiftUI
import WebKit

struct SVGTool: ToolView {
    static let meta = ToolMeta(
        id: "svg", name: "SVG 工具", category: .image, layout: .stacked,
        symbol: "scribble.variable",
        aliases: ["svg", "vector", "path", "svggj"]
    )

    private static let sample = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none"
         stroke="currentColor" stroke-width="2" stroke-linecap="round">
      <!-- 一个简单的图标 -->
      <path d="M12 2 L2 7 L12 12 L22 7 Z" />
      <path d="M2 17 L12 22 L22 17" />
      <path d="M2 12 L12 17 L22 12" />
    </svg>
    """

    enum Output: Hashable, CaseIterable {
        case minified, swiftUIPath, dataURL

        var label: String {
            switch self {
            case .minified:    return "压缩"
            case .swiftUIPath: return "SwiftUI Path"
            case .dataURL:     return "Data URL"
            }
        }
    }

    @State private var source = SVGTool.sample
    @State private var output: Output = .minified

    init() {}

    var body: some View {
        StackLayout(status: status) {
            OptionLabel(text: "输出")
            BentoSegments(options: Output.allCases.map { ($0, $0.label) }, selection: $output)
            Spacer()
            CopyButton(value: outputText, compact: false)
        } content: {
            HStack(spacing: Tokens.gapCard) {
                Card(title: "SVG 源码", dot: ToolCategory.image.tint, meta: sourceMeta) {
                    CodeArea(text: $source, placeholder: "粘贴 SVG…")
                }
                Card(title: "预览", dot: ToolCategory.style.tint, meta: viewBoxText) {
                    SVGPreview(svg: source)
                        .padding(Tokens.padCard)
                }
                .frame(width: 260)
            }

            Card(title: output.label, dot: ToolCategory.formatting.tint, meta: outputMeta) {
                CodeArea(text: .constant(outputText), isEditable: false)
            }
            .frame(height: 190)
        }
    }

    // MARK: - 处理

    private var minified: String {
        var s = source
        // 去注释
        while let a = s.range(of: "<!--"), let b = s.range(of: "-->", range: a.upperBound..<s.endIndex) {
            s.removeSubrange(a.lowerBound..<b.upperBound)
        }
        // 折叠空白
        s = s.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        return s.replacingOccurrences(of: "> <", with: "><")
                .replacingOccurrences(of: " />", with: "/>")
    }

    /// 提取所有 path 的 d 属性，转成 SwiftUI Path 代码。
    /// 只处理 M/L/H/V/C/Q/Z 这些常见指令，弧线 A 需要手工补 —— 会在注释里说明。
    private var swiftUIPath: String {
        let ds = extractAttribute("d")
        guard !ds.isEmpty else { return "// 没有找到 <path d=\"…\">" }
        var lines = ["Path { p in"]
        var hasArc = false
        for (i, d) in ds.enumerated() {
            lines.append("    // path \(i + 1)")
            let (code, arc) = Self.convertPathData(d)
            hasArc = hasArc || arc
            lines += code.map { "    \($0)" }
        }
        lines.append("}")
        if hasArc {
            lines.append("// ⚠︎ 含弧线指令 A/a，SwiftUI 需用 addArc 手工替换")
        }
        if let vb = viewBox {
            lines.append("// viewBox \(vb) — 记得 .frame() 或 .scaleEffect() 适配目标尺寸")
        }
        return lines.joined(separator: "\n")
    }

    static func convertPathData(_ d: String) -> (lines: [String], hasArc: Bool) {
        var out: [String] = []
        var hasArc = false
        var numbers: [Double] = []
        var command: Character?

        func flush() {
            guard let c = command else { return }
            switch c {
            case "M", "L":
                for i in stride(from: 0, to: numbers.count - 1, by: 2) {
                    let fn = (c == "M" && i == 0) ? "move" : "addLine"
                    out.append("p.\(fn)(to: CGPoint(x: \(g(numbers[i])), y: \(g(numbers[i + 1]))))")
                }
            case "H":
                for n in numbers { out.append("p.addLine(to: CGPoint(x: \(g(n)), y: /* 上一点 y */ 0))") }
            case "V":
                for n in numbers { out.append("p.addLine(to: CGPoint(x: /* 上一点 x */ 0, y: \(g(n))))") }
            case "C":
                for i in stride(from: 0, to: numbers.count - 5, by: 6) {
                    out.append("p.addCurve(to: CGPoint(x: \(g(numbers[i+4])), y: \(g(numbers[i+5]))), control1: CGPoint(x: \(g(numbers[i])), y: \(g(numbers[i+1]))), control2: CGPoint(x: \(g(numbers[i+2])), y: \(g(numbers[i+3]))))")
                }
            case "Q":
                for i in stride(from: 0, to: numbers.count - 3, by: 4) {
                    out.append("p.addQuadCurve(to: CGPoint(x: \(g(numbers[i+2])), y: \(g(numbers[i+3]))), control: CGPoint(x: \(g(numbers[i])), y: \(g(numbers[i+1]))))")
                }
            case "Z", "z":
                out.append("p.closeSubpath()")
            case "A", "a":
                hasArc = true
                out.append("// A \(numbers.map { g($0) }.joined(separator: " ")) — 需手工转 addArc")
            default:
                out.append("// 未处理指令 \(c)")
            }
            numbers = []
        }

        var buffer = ""
        for ch in d {
            if ch.isLetter {
                if !buffer.isEmpty { numbers.append(Double(buffer) ?? 0); buffer = "" }
                flush()
                command = ch
            } else if ch.isNumber || ch == "." || ch == "-" {
                if ch == "-", !buffer.isEmpty { numbers.append(Double(buffer) ?? 0); buffer = "" }
                buffer.append(ch)
            } else {
                if !buffer.isEmpty { numbers.append(Double(buffer) ?? 0); buffer = "" }
            }
        }
        if !buffer.isEmpty { numbers.append(Double(buffer) ?? 0) }
        flush()
        return (out, hasArc)
    }

    private static func g(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%g", v)
    }

    private var dataURL: String {
        let encoded = Data(minified.utf8).base64EncodedString()
        return "data:image/svg+xml;base64,\(encoded)"
    }

    private var outputText: String {
        switch output {
        case .minified:    return minified
        case .swiftUIPath: return swiftUIPath
        case .dataURL:     return dataURL
        }
    }

    // MARK: - 解析辅助

    private func extractAttribute(_ name: String) -> [String] {
        var out: [String] = []
        var rest = Substring(source)
        while let r = rest.range(of: "\(name)=\"") {
            let after = rest[r.upperBound...]
            guard let end = after.firstIndex(of: "\"") else { break }
            out.append(String(after[..<end]))
            rest = after[end...]
        }
        return out
    }

    private var viewBox: String? { extractAttribute("viewBox").first }
    private var viewBoxText: String { viewBox.map { "viewBox \($0)" } ?? "无 viewBox" }

    private var sourceMeta: String {
        "\(source.count) 字符 · \(extractAttribute("d").count) 个 path"
    }

    private var outputMeta: String {
        switch output {
        case .minified:
            let saved = source.count - minified.count
            return "\(minified.count) 字符（省 \(saved)）"
        case .swiftUIPath: return "\(swiftUIPath.components(separatedBy: "\n").count) 行"
        case .dataURL:     return "\(dataURL.count) 字符"
        }
    }

    private var status: StatusLine {
        if source.trimmed.isEmpty {
            return StatusLine(level: .idle, text: "粘贴 SVG 源码", trailing: "SVG", trailingKey: "⌄")
        }
        guard source.contains("<svg") else {
            return StatusLine(level: .error, text: "没有找到 <svg> 标签", trailing: "SVG", trailingKey: "⌄")
        }
        if viewBox == nil {
            return StatusLine(level: .warning,
                              text: "缺少 viewBox — 缩放时会出问题，建议补上",
                              trailing: "SVG", trailingKey: "⌄")
        }
        let saved = source.count - minified.count
        return StatusLine(level: .ok,
                          text: "\(extractAttribute("d").count) 个 path · 压缩可省 \(saved) 字符",
                          trailing: "SVG", trailingKey: "⌄")
    }
}

/// 用 WKWebView 渲染 —— macOS 没有能直接渲染任意 SVG 字符串的原生控件
private struct SVGPreview: NSViewRepresentable {
    let svg: String

    func makeNSView(context: Context) -> WKWebView {
        let web = WKWebView()
        web.setValue(false, forKey: "drawsBackground")
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        let html = """
        <html><head><meta charset="utf-8"><style>
        html,body{margin:0;height:100%;display:grid;place-items:center;
          color:\(nsAppearanceIsDark ? "#fff" : "#000");}
        svg{max-width:92%;max-height:92%;}
        </style></head><body>\(svg)</body></html>
        """
        web.loadHTMLString(html, baseURL: nil)
    }

    private var nsAppearanceIsDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
