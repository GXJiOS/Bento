import SwiftUI

struct JSONTool: ToolView {
    static let meta = ToolMeta(
        id: "json", name: "JSON 工具箱", category: .formatting, layout: .dual,
        symbol: "curlybraces",
        aliases: ["json", "format", "pretty", "gsh", "gjx"]
    )

    enum Mode: Hashable, CaseIterable {
        case pretty, minify, escape, unescape, query

        var label: String {
            switch self {
            case .pretty:   return "格式化"
            case .minify:   return "压缩"
            case .escape:   return "转义"
            case .unescape: return "去转义"
            case .query:    return "查询"
            }
        }
    }

    private static let sample = """
        {"user":{"id":1,"name":"gxj","roles":["admin","dev"],"profile":{"city":"洛阳","active":true}},"ts":1735689600}
        """

    @State private var input = JSONTool.sample
    @State private var mode: Mode = .pretty
    @State private var sortKeys = false
    @State private var indent = 2
    @State private var path = "$.user.roles[0]"

    init() {}

    var body: some View {
        ConverterView(
            input: $input,
            output: result.text,
            error: result.error,
            category: .formatting,
            placeholder: "粘贴 JSON…",
            okText: okText,
            trailing: stats,
            memoryKey: Self.meta.id
        ) {
            OptionLabel(text: "模式")
            BentoSegments(options: Mode.allCases.map { ($0, $0.label) }, selection: $mode)
            if mode == .pretty {
                BentoCheck(label: "排序键", isOn: $sortKeys)
                OptionLabel(text: "缩进")
                BentoSegments(options: [(2, "2"), (4, "4"), (0, "Tab")], selection: $indent)
            } else if mode == .query {
                TextField("$.a.b[0]", text: $path)
                    .textFieldStyle(.plain)
                    .font(Tokens.mono)
                    .padding(.horizontal, 9)
                    .frame(width: 240, height: 26)
                    .sunkenSurface(radius: 6)
                Text("支持 . 下标 · [n] · [*]")
                    .font(.system(size: 12)).foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }

    private var okText: String {
        switch mode {
        case .pretty:   return "格式化成功"
        case .minify:   return "压缩成功"
        case .escape:   return "已转义为字符串字面量"
        case .unescape: return "已还原"
        case .query:    return "查询成功"
        }
    }

    // MARK: - 计算

    private var result: (text: String, error: String?) {
        let src = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !src.isEmpty else { return ("", nil) }

        if mode == .escape {
            let escaped = src
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\t", with: "\\t")
                .replacingOccurrences(of: "\r", with: "\\r")
            return ("\"\(escaped)\"", nil)
        }
        if mode == .unescape {
            var s = src
            if s.hasPrefix("\""), s.hasSuffix("\""), s.count >= 2 {
                s = String(s.dropFirst().dropLast())
            }
            return (s.replacingOccurrences(of: "\\n", with: "\n")
                     .replacingOccurrences(of: "\\t", with: "\t")
                     .replacingOccurrences(of: "\\r", with: "\r")
                     .replacingOccurrences(of: "\\\"", with: "\"")
                     .replacingOccurrences(of: "\\\\", with: "\\"), nil)
        }

        guard let data = src.data(using: .utf8) else { return ("", "输入不是有效的 UTF-8") }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            return ("", Self.friendly(error, in: src))
        }

        switch mode {
        case .minify:
            return (Self.serialize(object, pretty: false, sorted: false, indent: 0), nil)
        case .pretty:
            return (Self.serialize(object, pretty: true, sorted: sortKeys, indent: indent), nil)
        case .query:
            guard let found = Self.query(object, path: path) else {
                return ("", "路径 \(path) 没有匹配到任何值")
            }
            return (Self.serialize(found, pretty: true, sorted: sortKeys, indent: indent), nil)
        default:
            return ("", nil)
        }
    }

    /// 状态栏右侧顺手给出结构统计，省得再开一个工具
    private var stats: String {
        guard let data = input.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { return "JSON" }
        let (keys, depth, nodes) = Self.measure(obj)
        return "\(keys) 键 · 深 \(depth) · \(nodes) 节点"
    }

    // MARK: - 序列化

    private static func serialize(_ object: Any, pretty: Bool, sorted: Bool, indent: Int) -> String {
        var opts: JSONSerialization.WritingOptions = [.withoutEscapingSlashes, .fragmentsAllowed]
        if pretty { opts.insert(.prettyPrinted) }
        if sorted { opts.insert(.sortedKeys) }
        guard let out = try? JSONSerialization.data(withJSONObject: object, options: opts),
              let s = String(data: out, encoding: .utf8) else { return "" }
        guard pretty, indent != 2 else { return s }
        // JSONSerialization 固定 2 空格缩进，按行首空格数换算成目标缩进
        return s.components(separatedBy: "\n").map { line -> String in
            let spaces = line.prefix(while: { $0 == " " }).count
            let level = spaces / 2
            let unit = indent == 0 ? "\t" : String(repeating: " ", count: indent)
            return String(repeating: unit, count: level) + line.dropFirst(spaces)
        }.joined(separator: "\n")
    }

    // MARK: - JSONPath 子集

    /// 只实现日常够用的三种：`.key`、`[n]`、`[*]`。完整 JSONPath 规范不值得为自用工具实现。
    static func query(_ root: Any, path: String) -> Any? {
        var current: Any? = root
        var token = ""
        var i = path.startIndex

        func consume() -> Bool {
            defer { token = "" }
            guard !token.isEmpty, token != "$" else { return true }
            guard let dict = current as? [String: Any] else { return false }
            current = dict[token]
            return current != nil
        }

        while i < path.endIndex {
            let c = path[i]
            if c == "." {
                if !consume() { return nil }
            } else if c == "[" {
                if !consume() { return nil }
                guard let close = path[i...].firstIndex(of: "]") else { return nil }
                let idx = String(path[path.index(after: i)..<close])
                guard let arr = current as? [Any] else { return nil }
                if idx == "*" {
                    current = arr
                } else if let n = Int(idx) {
                    let real = n < 0 ? arr.count + n : n
                    guard real >= 0, real < arr.count else { return nil }
                    current = arr[real]
                } else { return nil }
                i = path.index(after: close)
                continue
            } else {
                token.append(c)
            }
            i = path.index(after: i)
        }
        if !consume() { return nil }
        return current
    }

    // MARK: - 统计与报错

    private static func measure(_ obj: Any, depth: Int = 1) -> (keys: Int, depth: Int, nodes: Int) {
        switch obj {
        case let d as [String: Any]:
            var k = d.count, maxD = depth, n = 1
            for v in d.values {
                let r = measure(v, depth: depth + 1)
                k += r.keys; maxD = max(maxD, r.depth); n += r.nodes
            }
            return (k, maxD, n)
        case let a as [Any]:
            var maxD = depth, n = 1, k = 0
            for v in a {
                let r = measure(v, depth: depth + 1)
                k += r.keys; maxD = max(maxD, r.depth); n += r.nodes
            }
            return (k, maxD, n)
        default:
            return (0, depth, 1)
        }
    }

    /// NSError 的 debugDescription 里带字符偏移，换算成行列比「Invalid value around line 0」有用
    private static func friendly(_ error: Error, in src: String) -> String {
        let ns = error as NSError
        let desc = ns.userInfo[NSDebugDescriptionErrorKey] as? String ?? ns.localizedDescription
        if let range = desc.range(of: #"character (\d+)"#, options: .regularExpression),
           let offset = Int(desc[range].components(separatedBy: " ").last ?? "") {
            let prefix = src.prefix(offset)
            let line = prefix.components(separatedBy: "\n").count
            let col = prefix.components(separatedBy: "\n").last?.count ?? 0
            return "JSON 解析失败 · 第 \(line) 行第 \(col + 1) 列 — \(desc)"
        }
        return "JSON 解析失败 · \(desc)"
    }
}
