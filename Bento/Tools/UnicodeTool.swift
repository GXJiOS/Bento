import SwiftUI

struct UnicodeTool: ToolView {
    static let meta = ToolMeta(
        id: "unicode", name: "Unicode 转义", category: .encoding, layout: .dual,
        symbol: "textformat",
        aliases: ["unicode", "u", "escape", "zy", "unizy"]
    )

    /// 输出格式。前三种按 UTF-16 code unit 走（emoji 会拆成代理对，
    /// 这正是 JS/Java 源码里的样子）；`\u{...}` 按 Unicode 标量走。
    enum Style: Hashable {
        case backslashU      // \u4E16
        case braces          // \u{1F30D}
        case htmlDecimal     // &#19990;
        case htmlHex         // &#x4E16;

        var label: String {
            switch self {
            case .backslashU:  return #"\uXXXX"#
            case .braces:      return #"\u{...}"#
            case .htmlDecimal: return "&#123;"
            case .htmlHex:     return "&#x7B;"
            }
        }
    }

    @State private var input = "Hello, 世界 🌍"
    @State private var direction: ConvertDirection = .encode
    @State private var style: Style = .backslashU
    @State private var onlyNonASCII = true
    @State private var lowercase = false

    init() {}

    var body: some View {
        ConverterView(
            input: $input,
            output: result.text,
            error: result.error,
            okText: direction.okText,
            trailing: scalarInfo,
            onSwap: { let out = result.text; direction = direction.toggled; input = out },
            memoryKey: Self.meta.id
        ) {
            OptionLabel(text: "方向")
            DirectionPicker(direction: $direction)
            if direction == .encode {
                BentoSegments(options: [(Style.backslashU, Style.backslashU.label),
                                        (.braces, Style.braces.label),
                                        (.htmlDecimal, Style.htmlDecimal.label),
                                        (.htmlHex, Style.htmlHex.label)],
                              selection: $style)
                BentoCheck(label: "只转非 ASCII", isOn: $onlyNonASCII)
                BentoCheck(label: "小写十六进制", isOn: $lowercase)
            } else {
                Text("自动识别 \\uXXXX · \\u{...} · &#123; · &#x7B; · \\xFF")
                    .font(.system(size: 12)).foregroundStyle(.tertiary)
            }
        }
    }

    private var result: (text: String, error: String?) {
        guard !input.isEmpty else { return ("", nil) }
        return direction == .encode ? (encode(), nil) : decode()
    }

    // MARK: - 编码

    private func encode() -> String {
        let hexFormat = lowercase ? "%04x" : "%04X"
        var out = ""

        if style == .braces {
            for scalar in input.unicodeScalars {
                if onlyNonASCII && scalar.isASCII {
                    out.unicodeScalars.append(scalar)
                } else {
                    out += String(format: "\\u{\(lowercase ? "%x" : "%X")}", scalar.value)
                }
            }
            return out
        }

        for unit in input.utf16 {
            if onlyNonASCII && unit < 0x80, let s = UnicodeScalar(unit) {
                out.unicodeScalars.append(s)
                continue
            }
            switch style {
            case .backslashU:  out += String(format: "\\u\(hexFormat)", unit)
            case .htmlDecimal: out += "&#\(unit);"
            case .htmlHex:     out += String(format: "&#x\(lowercase ? "%x" : "%X");", unit)
            case .braces:      break  // 上面已处理
            }
        }
        return out
    }

    // MARK: - 解码

    /// 一次扫描处理四种写法。代理对靠「先收集 UTF-16 单元再统一构造字符串」自然合并。
    private func decode() -> (String, String?) {
        var units: [UInt16] = []
        var scalars: [UnicodeScalar] = []
        var sawEscape = false

        func flushUnits() {
            guard !units.isEmpty else { return }
            scalars.append(contentsOf: String(utf16CodeUnits: units, count: units.count).unicodeScalars)
            units.removeAll()
        }

        let chars = Array(input)
        var i = 0
        while i < chars.count {
            // \uXXXX 或 \u{XXXXX} 或 \xFF
            if chars[i] == "\\", i + 1 < chars.count {
                let next = chars[i + 1]
                if next == "u" || next == "U" {
                    if i + 2 < chars.count, chars[i + 2] == "{" {
                        if let close = chars[(i + 3)...].firstIndex(of: "}") {
                            let hex = String(chars[(i + 3)..<close])
                            if let v = UInt32(hex, radix: 16), let s = UnicodeScalar(v) {
                                flushUnits(); scalars.append(s)
                                i = close + 1; sawEscape = true; continue
                            }
                        }
                    } else if i + 5 < chars.count {
                        let hex = String(chars[(i + 2)...(i + 5)])
                        if let v = UInt16(hex, radix: 16) {
                            units.append(v); i += 6; sawEscape = true; continue
                        }
                    }
                } else if next == "x", i + 3 < chars.count {
                    let hex = String(chars[(i + 2)...(i + 3)])
                    if let v = UInt16(hex, radix: 16) {
                        units.append(v); i += 4; sawEscape = true; continue
                    }
                }
            }
            // &#123; 或 &#x7B;
            if chars[i] == "&", i + 2 < chars.count, chars[i + 1] == "#" {
                if let close = chars[(i + 2)...].firstIndex(of: ";") {
                    let body = String(chars[(i + 2)..<close])
                    let isHex = body.lowercased().hasPrefix("x")
                    let digits = isHex ? String(body.dropFirst()) : body
                    if let v = UInt32(digits, radix: isHex ? 16 : 10) {
                        if v <= 0xFFFF, let u = UInt16(exactly: v) {
                            units.append(u)
                        } else if let s = UnicodeScalar(v) {
                            flushUnits(); scalars.append(s)
                        }
                        i = close + 1; sawEscape = true; continue
                    }
                }
            }
            for s in String(chars[i]).unicodeScalars {
                if s.value <= 0xFFFF { units.append(UInt16(s.value)) }
                else { flushUnits(); scalars.append(s) }
            }
            i += 1
        }
        flushUnits()

        var out = ""
        out.unicodeScalars.append(contentsOf: scalars)
        if !sawEscape { return (out, "没有发现转义序列 · 输入原样返回") }
        return (out, nil)
    }

    private var scalarInfo: String {
        let text = direction == .encode ? input : result.text
        return "\(text.unicodeScalars.count) 标量 · \(text.utf16.count) UTF-16"
    }
}
