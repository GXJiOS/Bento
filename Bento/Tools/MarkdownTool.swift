import SwiftUI

struct MarkdownTool: ToolView {
    static let meta = ToolMeta(
        id: "markdown", name: "Markdown 预览", category: .formatting, layout: .stacked,
        symbol: "doc.richtext",
        aliases: ["markdown", "md", "preview", "mdyl"]
    )

    private static let sample = """
        # Bento 设计规范

        视觉语言取自 **macOS 系统设置**：灰底 + 浮起卡片 + *分类语义色*。

        ## 令牌

        - `cardRadius` = 12
        - `padContent` = 14
        - 强调色读 `NSColor.controlAccentColor`

        > 层次色不用系统语义色 —— dark 下 controlBackground 比 underPage 更深，
        > 与「卡片浮在灰底上」相反。

        ```swift
        struct Card<Content: View>: View {
            var title: String?
        }
        ```

        1. Phase 0 骨架
        2. Phase 1 编解码
        3. Phase 2 格式化

        ---

        详见 [原型](file:///prototype.html)。
        """

    enum Block: Identifiable {
        case heading(Int, String)
        case paragraph(String)
        case bullet(String, Int)
        case ordered(Int, String)
        case code(String, String?)
        case quote([String])
        case rule

        var id: String {
            switch self {
            case .heading(let l, let t): return "h\(l)-\(t)"
            case .paragraph(let t):      return "p-\(t.prefix(40))"
            case .bullet(let t, let d):  return "b\(d)-\(t.prefix(40))"
            case .ordered(let n, let t): return "o\(n)-\(t.prefix(40))"
            case .code(let c, _):        return "c-\(c.prefix(40))"
            case .quote(let l):          return "q-\(l.first?.prefix(40) ?? "")"
            case .rule:                  return "hr-\(UUID().uuidString)"
            }
        }
    }

    @State private var input = MarkdownTool.sample

    init() {}

    var body: some View {
        StackLayout(status: status) {
            OptionLabel(text: "语法")
            Text("标题 · 列表 · 代码块 · 引用 · 分割线 · 行内强调与链接")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
            Spacer()
            CopyButton(value: input, compact: false)
        } content: {
            HStack(spacing: Tokens.gapCard) {
                Card(title: "MARKDOWN", dot: ToolCategory.formatting.tint, meta: meta) {
                    CodeArea(text: $input, placeholder: "写点 Markdown…")
                }
                Card(title: "预览", dot: ToolCategory.image.tint,
                     meta: "\(blocks.count) 个块") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(blocks) { render($0) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Tokens.padCard)
                    }
                    .scrollIndicators(.never)
                }
            }
        }
    }

    // MARK: - 渲染

    @ViewBuilder
    private func render(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(.system(size: [26.0, 21, 17, 15, 14, 13][min(level - 1, 5)],
                              weight: level <= 2 ? .bold : .semibold))
                .padding(.top, level <= 2 ? 6 : 2)

        case .paragraph(let text):
            Text(inline(text))
                .font(.system(size: 13.5))
                .lineSpacing(4)
                .textSelection(.enabled)

        case .bullet(let text, let depth):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.tertiary)
                Text(inline(text)).font(.system(size: 13.5)).lineSpacing(3)
            }
            .padding(.leading, CGFloat(depth) * 16)

        case .ordered(let n, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(n).").foregroundStyle(.tertiary).monospacedDigit()
                Text(inline(text)).font(.system(size: 13.5)).lineSpacing(3)
            }

        case .code(let code, let lang):
            VStack(alignment: .leading, spacing: 0) {
                if let lang, !lang.isEmpty {
                    Text(lang)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10).padding(.top, 7)
                }
                Text(code)
                    .font(Tokens.mono)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .sunkenSurface(radius: 8)

        case .quote(let lines):
            HStack(spacing: 10) {
                Rectangle().fill(Tokens.accent.opacity(0.5)).frame(width: 3)
                Text(inline(lines.joined(separator: " ")))
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .rule:
            Rectangle().fill(Tokens.separator).frame(height: 1).padding(.vertical, 2)
        }
    }

    /// 行内语法交给 Foundation 的 markdown 解析（**粗** *斜* `码` [链接]），
    /// 块级自己拆 —— SwiftUI 的 Text 渲染不了块级布局
    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(s)
    }

    // MARK: - 块级解析

    private var blocks: [Block] {
        var out: [Block] = []
        let lines = input.components(separatedBy: .newlines)
        var i = 0
        var paragraph: [String] = []
        var quote: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                out.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph.removeAll()
            }
        }
        func flushQuote() {
            if !quote.isEmpty { out.append(.quote(quote)); quote.removeAll() }
        }

        while i < lines.count {
            let raw = lines[i]
            let line = raw.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                flushParagraph(); flushQuote()
                let lang = String(line.dropFirst(3)).trimmed
                var body: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmed.hasPrefix("```") {
                    body.append(lines[i]); i += 1
                }
                i += 1
                out.append(.code(body.joined(separator: "\n"), lang.isEmpty ? nil : lang))
                continue
            }

            if line.isEmpty {
                flushParagraph(); flushQuote()
            } else if line.hasPrefix("#") {
                flushParagraph(); flushQuote()
                let level = line.prefix(while: { $0 == "#" }).count
                out.append(.heading(min(level, 6),
                                    String(line.dropFirst(level)).trimmed))
            } else if line == "---" || line == "***" || line == "___" {
                flushParagraph(); flushQuote()
                out.append(.rule)
            } else if line.hasPrefix("> ") || line == ">" {
                flushParagraph()
                quote.append(String(line.dropFirst(line == ">" ? 1 : 2)))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                flushParagraph(); flushQuote()
                let indentSpaces = raw.prefix(while: { $0 == " " }).count
                out.append(.bullet(String(line.dropFirst(2)), indentSpaces / 2))
            } else if let dot = line.firstIndex(of: "."),
                      let n = Int(line[line.startIndex..<dot]),
                      line.index(after: dot) < line.endIndex,
                      line[line.index(after: dot)] == " " {
                flushParagraph(); flushQuote()
                out.append(.ordered(n, String(line[line.index(dot, offsetBy: 2)...])))
            } else {
                flushQuote()
                paragraph.append(line)
            }
            i += 1
        }
        flushParagraph(); flushQuote()
        return out
    }

    private var meta: String {
        let words = input.split(whereSeparator: { $0.isWhitespace }).count
        return "\(input.components(separatedBy: .newlines).count) 行 · \(words) 词"
    }

    private var status: StatusLine {
        input.trimmed.isEmpty
            ? StatusLine(level: .idle, text: "等待输入", trailing: "CommonMark 子集", trailingKey: "⌄")
            : StatusLine(level: .ok,
                         text: "已解析 \(blocks.count) 个块 · 行内语法走 Foundation",
                         trailing: "CommonMark 子集", trailingKey: "⌄")
    }
}
