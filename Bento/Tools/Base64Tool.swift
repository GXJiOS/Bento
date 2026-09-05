import SwiftUI

struct Base64Tool: ToolView {
    static let meta = ToolMeta(
        id: "base64", name: "Base64 编解码", category: .encoding, layout: .dual,
        symbol: "arrow.left.arrow.right",
        aliases: ["b64", "base64", "bianma", "bjm"]
    )

    @State private var input = "Hello, 世界 🌍"
    @State private var direction: ConvertDirection = .encode
    @State private var urlSafe = false
    @State private var wrapLines = false

    init() {}

    var body: some View {
        ConverterView(
            input: $input,
            output: result.text,
            error: result.error,
            okText: direction.okText,
            onSwap: { let out = result.text; direction = direction.toggled; input = out },
            onLoadFile: load,
            memoryKey: Self.meta.id
        ) {
            OptionLabel(text: "方向")
            DirectionPicker(direction: $direction)
            BentoCheck(label: "URL-safe", isOn: $urlSafe)
            BentoCheck(label: "每 76 字符换行", isOn: $wrapLines)
        }
    }

    private var result: (text: String, error: String?) {
        guard !input.isEmpty else { return ("", nil) }
        if direction == .encode {
            var s = Data(input.utf8).base64EncodedString()
            if urlSafe {
                s = s.replacingOccurrences(of: "+", with: "-")
                     .replacingOccurrences(of: "/", with: "_")
                     .replacingOccurrences(of: "=", with: "")
            }
            if wrapLines { s = s.chunked(76).joined(separator: "\n") }
            return (s, nil)
        } else {
            var t = input.filter { !$0.isWhitespace }
            if urlSafe {
                t = t.replacingOccurrences(of: "-", with: "+")
                     .replacingOccurrences(of: "_", with: "/")
            }
            t += String(repeating: "=", count: (4 - t.count % 4) % 4)  // URL-safe 常去掉尾部 =
            guard let data = Data(base64Encoded: t, options: [.ignoreUnknownCharacters]) else {
                return ("", "无效的 Base64 · 出现字符集外的字符")
            }
            guard let s = String(data: data, encoding: .utf8) else {
                return ("", "解码成功但不是 UTF-8 文本 · \(data.count) 字节二进制")
            }
            return (s, nil)
        }
    }

    private func load(_ url: URL) {
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            input = text
        } else if let data = try? Data(contentsOf: url) {
            // 二进制文件直接给出 Base64，方向切到解码便于回读
            input = data.base64EncodedString()
            direction = .decode
        }
    }
}

extension String {
    /// 按固定长度切块（Base64 换行、hex 分组都用）
    func chunked(_ size: Int) -> [String] {
        guard size > 0, !isEmpty else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            let start = index(startIndex, offsetBy: $0)
            let end = index(start, offsetBy: Swift.min(size, count - $0))
            return String(self[start..<end])
        }
    }
}
