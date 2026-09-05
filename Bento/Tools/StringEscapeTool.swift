import SwiftUI

struct StringEscapeTool: ToolView {
    static let meta = ToolMeta(
        id: "escape", name: "字符串转义", category: .encoding, layout: .dual,
        symbol: "quote.opening",
        aliases: ["escape", "quote", "zy", "zfczy"]
    )

    enum Target: Hashable, CaseIterable {
        case json, swift, shell, regex

        var label: String {
            switch self {
            case .json:  return "JSON"
            case .swift: return "Swift"
            case .shell: return "Shell"
            case .regex: return "正则"
            }
        }

        var note: String {
            switch self {
            case .json:  return "RFC 8259 · 控制字符走 \\uXXXX"
            case .swift: return "Swift 字面量 · 标量走 \\u{...}"
            case .shell: return "单引号包裹 · 内部 ' 拆成 '\\''"
            case .regex: return "转义 ICU 正则元字符"
            }
        }
    }

    @State private var input = "行1\t\"引号\"\n行2 \\ 反斜杠"
    @State private var direction: ConvertDirection = .encode
    @State private var target: Target = .json
    @State private var wrapQuotes = true

    init() {}

    var body: some View {
        ConverterView(
            input: $input,
            output: result.text,
            error: result.error,
            okText: direction.okText,
            trailing: target.note,
            onSwap: { let out = result.text; direction = direction.toggled; input = out },
            memoryKey: Self.meta.id
        ) {
            OptionLabel(text: "方向")
            DirectionPicker(direction: $direction)
            OptionLabel(text: "目标")
            BentoSegments(options: Target.allCases.map { ($0, $0.label) }, selection: $target)
            if direction == .encode && target != .regex {
                BentoCheck(label: "带引号", isOn: $wrapQuotes)
            }
        }
    }

    private var result: (text: String, error: String?) {
        guard !input.isEmpty else { return ("", nil) }
        return direction == .encode ? (encode(), nil) : decode()
    }

    // MARK: - 编码

    private func encode() -> String {
        switch target {
        case .json:  return quoted(escapeJSONLike(braces: false), #"""#)
        case .swift: return quoted(escapeJSONLike(braces: true), #"""#)
        case .shell: return quoted(input.replacingOccurrences(of: "'", with: #"'\''"#), "'")
        case .regex:
            let metas = Set(#".^$*+?()[]{}|\/"#)
            return String(input.flatMap { metas.contains($0) ? ["\\", $0] : [$0] })
        }
    }

    private func quoted(_ s: String, _ q: String) -> String {
        wrapQuotes ? q + s + q : s
    }

    /// JSON 与 Swift 的转义规则只差「非打印字符用 \uXXXX 还是 \u{...}」
    private func escapeJSONLike(braces: Bool) -> String {
        var out = ""
        for scalar in input.unicodeScalars {
            switch scalar {
            case "\"":     out += #"\""#
            case "\\":     out += #"\\"#
            case "\n":     out += #"\n"#
            case "\r":     out += #"\r"#
            case "\t":     out += #"\t"#
            case "\u{08}": out += braces ? #"\u{8}"# : #"\b"#
            case "\u{0C}": out += braces ? #"\u{C}"# : #"\f"#
            case "\u{00}": out += braces ? #"\0"# : #"\u0000"#
            default:
                if scalar.value < 0x20 {
                    out += braces ? String(format: "\\u{%X}", scalar.value)
                                  : String(format: "\\u%04X", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out
    }

    // MARK: - 解码

    private func decode() -> (String, String?) {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if target == .shell {
            if s.count >= 2, s.hasPrefix("'"), s.hasSuffix("'") { s = String(s.dropFirst().dropLast()) }
            return (s.replacingOccurrences(of: #"'\''"#, with: "'"), nil)
        }
        if target == .regex {
            var out = ""
            var i = s.startIndex
            while i < s.endIndex {
                if s[i] == "\\", s.index(after: i) < s.endIndex {
                    i = s.index(after: i)
                }
                out.append(s[i])
                i = s.index(after: i)
            }
            return (out, nil)
        }

        // JSON / Swift：去掉外层引号后逐个还原
        if s.count >= 2, s.hasPrefix("\""), s.hasSuffix("\"") { s = String(s.dropFirst().dropLast()) }
        var out = ""
        let chars = Array(s)
        var i = 0
        var bad = false
        while i < chars.count {
            guard chars[i] == "\\", i + 1 < chars.count else {
                out.append(chars[i]); i += 1; continue
            }
            let c = chars[i + 1]
            i += 2
            switch c {
            case "n": out.append("\n")
            case "r": out.append("\r")
            case "t": out.append("\t")
            case "b": out.append("\u{08}")
            case "f": out.append("\u{0C}")
            case "0": out.append("\u{00}")
            case "\"", "\\", "'", "/": out.append(c)
            case "u":
                if i < chars.count, chars[i] == "{" {
                    if let close = chars[(i + 1)...].firstIndex(of: "}"),
                       let v = UInt32(String(chars[(i + 1)..<close]), radix: 16),
                       let scalar = UnicodeScalar(v) {
                        out.unicodeScalars.append(scalar); i = close + 1
                    } else { bad = true }
                } else if i + 3 < chars.count,
                          let v = UInt16(String(chars[i...(i + 3)]), radix: 16) {
                    out += String(utf16CodeUnits: [v], count: 1)
                    i += 4
                } else { bad = true }
            default:
                out.append("\\"); out.append(c)
            }
        }
        return (out, bad ? "存在不完整的 \\u 转义序列" : nil)
    }
}
