import SwiftUI

struct CaseTool: ToolView {
    static let meta = ToolMeta(
        id: "case", name: "命名转换", category: .formatting, layout: .dual,
        symbol: "textformat.abc",
        aliases: ["case", "camel", "snake", "kebab", "mm", "mingming"]
    )

    enum Style: Hashable, CaseIterable {
        case camel, pascal, snake, kebab, constant, dot, title, sentence

        var label: String {
            switch self {
            case .camel:    return "camelCase"
            case .pascal:   return "PascalCase"
            case .snake:    return "snake_case"
            case .kebab:    return "kebab-case"
            case .constant: return "CONST_CASE"
            case .dot:      return "dot.case"
            case .title:    return "Title Case"
            case .sentence: return "Sentence case"
            }
        }
    }

    @State private var input = """
        user_id
        HTTPServerConfig
        parse-json-response
        MAX_RETRY_COUNT
        getUserName2FA
        """
    @State private var style: Style = .camel

    init() {}

    var body: some View {
        ConverterView(
            input: $input,
            output: output,
            category: .formatting,
            placeholder: "每行一个标识符…",
            okText: "已转换 \(lineCount) 行",
            trailing: style.label,
            memoryKey: Self.meta.id
        ) {
            OptionLabel(text: "目标")
            BentoSegments(options: Array(Style.allCases.prefix(4)).map { ($0, $0.label) },
                          selection: $style)
            BentoSegments(options: Array(Style.allCases.suffix(4)).map { ($0, $0.label) },
                          selection: $style)
            Spacer()
        }
    }

    private var lineCount: Int {
        input.components(separatedBy: .newlines).filter { !$0.trimmed.isEmpty }.count
    }

    private var output: String {
        input.components(separatedBy: .newlines).map { line -> String in
            let t = line.trimmed
            return t.isEmpty ? "" : Self.convert(t, to: style)
        }.joined(separator: "\n")
    }

    // MARK: - 分词

    /// 难点在连续大写：`HTTPServer` 要切成 HTTP|Server 而不是 H|T|T|P|Server，
    /// 规则是「大写序列后面跟着小写字母时，在最后一个大写前断开」。
    static func words(_ s: String) -> [String] {
        var result: [String] = []
        for chunk in s.split(whereSeparator: { "_-. /:".contains($0) }) {
            var current = ""
            let chars = Array(chunk)
            for (i, c) in chars.enumerated() {
                if current.isEmpty { current.append(c); continue }
                let prev = chars[i - 1]
                let next = i + 1 < chars.count ? chars[i + 1] : nil

                let lowerToUpper = prev.isLowercase && c.isUppercase
                let acronymEnd = prev.isUppercase && c.isUppercase && (next?.isLowercase ?? false)
                let digitBoundary = (prev.isNumber != c.isNumber)

                if lowerToUpper || acronymEnd || digitBoundary {
                    result.append(current)
                    current = String(c)
                } else {
                    current.append(c)
                }
            }
            if !current.isEmpty { result.append(current) }
        }
        return result.filter { !$0.isEmpty }
    }

    static func convert(_ s: String, to style: Style) -> String {
        let w = words(s)
        guard !w.isEmpty else { return s }
        let lower = w.map { $0.lowercased() }

        switch style {
        case .camel:
            return lower.first! + lower.dropFirst().map { $0.uppercasedFirst() }.joined()
        case .pascal:
            return lower.map { $0.uppercasedFirst() }.joined()
        case .snake:
            return lower.joined(separator: "_")
        case .kebab:
            return lower.joined(separator: "-")
        case .constant:
            return lower.map { $0.uppercased() }.joined(separator: "_")
        case .dot:
            return lower.joined(separator: ".")
        case .title:
            return lower.map { $0.uppercasedFirst() }.joined(separator: " ")
        case .sentence:
            return (lower.first!.uppercasedFirst() + " " + lower.dropFirst().joined(separator: " "))
                .trimmed
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
