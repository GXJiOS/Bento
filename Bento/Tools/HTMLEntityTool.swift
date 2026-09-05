import SwiftUI

struct HTMLEntityTool: ToolView {
    static let meta = ToolMeta(
        id: "htmlentity", name: "HTML 实体", category: .encoding, layout: .dual,
        symbol: "chevron.left.slash.chevron.right",
        aliases: ["html", "entity", "amp", "st", "htmlst"]
    )

    /// 只处理会破坏 HTML 结构的五个字符 —— 其余照原样，避免把中文全炸成 &#xxx;
    private static let named: [(Character, String)] = [
        ("&", "&amp;"), ("<", "&lt;"), (">", "&gt;"), ("\"", "&quot;"), ("'", "&#39;"),
    ]

    /// 解码用的命名实体表（常用子集）
    private static let decodeMap: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "copy": "©", "reg": "®", "trade": "™", "hellip": "…", "mdash": "—", "ndash": "–",
        "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "bull": "•", "middot": "·",
        "times": "×", "divide": "÷", "deg": "°", "plusmn": "±", "laquo": "«", "raquo": "»",
        "euro": "€", "pound": "£", "yen": "¥", "cent": "¢", "sect": "§", "para": "¶",
        "dagger": "†", "permil": "‰", "larr": "←", "rarr": "→", "harr": "↔", "ne": "≠",
        "le": "≤", "ge": "≥", "infin": "∞", "alpha": "α", "beta": "β", "gamma": "γ",
    ]

    @State private var input = "<a href=\"?a=1&b=2\">点击 &amp; 查看</a>"
    @State private var direction: ConvertDirection = .encode
    @State private var allNonASCII = false

    init() {}

    var body: some View {
        ConverterView(
            input: $input,
            output: result.text,
            error: result.error,
            placeholder: "粘贴 HTML 片段…",
            okText: direction.okText,
            trailing: "HTML5",
            onSwap: { let out = result.text; direction = direction.toggled; input = out },
            memoryKey: Self.meta.id
        ) {
            OptionLabel(text: "方向")
            DirectionPicker(direction: $direction)
            if direction == .encode {
                BentoCheck(label: "非 ASCII 也转成 &#x…;", isOn: $allNonASCII)
                Text("默认只转 & < > \" '").font(.system(size: 12)).foregroundStyle(.tertiary)
            } else {
                Text("支持 \(Self.decodeMap.count) 个命名实体 + &#123; + &#x7B;")
                    .font(.system(size: 12)).foregroundStyle(.tertiary)
            }
        }
    }

    private var result: (text: String, error: String?) {
        guard !input.isEmpty else { return ("", nil) }
        return direction == .encode ? (encode(), nil) : (decode(), nil)
    }

    private func encode() -> String {
        var out = ""
        for ch in input {
            if let hit = Self.named.first(where: { $0.0 == ch }) {
                out += hit.1
            } else if allNonASCII, !ch.isASCII {
                for scalar in String(ch).unicodeScalars {
                    out += String(format: "&#x%X;", scalar.value)
                }
            } else {
                out.append(ch)
            }
        }
        return out
    }

    private func decode() -> String {
        var out = ""
        let chars = Array(input)
        var i = 0
        while i < chars.count {
            guard chars[i] == "&",
                  let semi = chars[(i + 1)...].prefix(12).firstIndex(of: ";") else {
                out.append(chars[i]); i += 1; continue
            }
            let body = String(chars[(i + 1)..<semi])
            if body.hasPrefix("#") {
                let raw = String(body.dropFirst())
                let isHex = raw.lowercased().hasPrefix("x")
                let digits = isHex ? String(raw.dropFirst()) : raw
                if let v = UInt32(digits, radix: isHex ? 16 : 10), let s = UnicodeScalar(v) {
                    out.unicodeScalars.append(s); i = semi + 1; continue
                }
            } else if let mapped = Self.decodeMap[body] {
                out += mapped; i = semi + 1; continue
            }
            out.append(chars[i]); i += 1
        }
        return out
    }
}
