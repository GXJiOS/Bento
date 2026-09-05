import Foundation

/// 够用的 YAML 子集。
///
/// 系统没有原生 YAML，而完整规范（锚点、别名、标签、多文档、复杂键、流式集合）
/// 大得离谱。日常需要的只是「读一段 k8s / CI / docker-compose 配置」，
/// 所以这里只实现常见子集，**不支持的写法会明确报错而不是猜**。
enum YAMLLite {

    struct Unsupported: LocalizedError {
        let line: Int
        let reason: String
        var errorDescription: String? { "第 \(line) 行：\(reason)" }
    }

    // MARK: - 生成（JSON → YAML）

    static func dump(_ value: Any, indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        switch value {
        case let dict as [String: Any]:
            if dict.isEmpty { return "\(pad){}" }
            return dict.keys.sorted().map { key -> String in
                let v = dict[key]!
                if isScalar(v) {
                    return "\(pad)\(quoteKey(key)): \(scalar(v))"
                }
                if let arr = v as? [Any], arr.isEmpty { return "\(pad)\(quoteKey(key)): []" }
                if let d = v as? [String: Any], d.isEmpty { return "\(pad)\(quoteKey(key)): {}" }
                return "\(pad)\(quoteKey(key)):\n\(dump(v, indent: indent + 1))"
            }.joined(separator: "\n")

        case let arr as [Any]:
            if arr.isEmpty { return "\(pad)[]" }
            return arr.map { item -> String in
                if isScalar(item) { return "\(pad)- \(scalar(item))" }
                // 嵌套结构：先输出 "- "，再把子块的首行提上来
                let block = dump(item, indent: indent + 1)
                let lines = block.components(separatedBy: "\n")
                let first = lines[0].drop(while: { $0 == " " })
                let rest = lines.dropFirst()
                return (["\(pad)- \(first)"] + rest).joined(separator: "\n")
            }.joined(separator: "\n")

        default:
            return "\(pad)\(scalar(value))"
        }
    }

    private static func isScalar(_ v: Any) -> Bool {
        !(v is [String: Any]) && !(v is [Any])
    }

    private static func quoteKey(_ k: String) -> String {
        let needsQuote = k.isEmpty || k.contains(":") || k.contains("#") || k.first == " "
        return needsQuote ? "\"\(k)\"" : k
    }

    private static func scalar(_ v: Any) -> String {
        switch v {
        case is NSNull: return "null"
        case let n as NSNumber:
            return CFGetTypeID(n) == CFBooleanGetTypeID() ? (n.boolValue ? "true" : "false") : "\(n)"
        case let s as String:
            if s.isEmpty { return "\"\"" }
            if s.contains("\n") {
                // 块标量，保留换行
                return "|\n" + s.components(separatedBy: "\n")
                    .map { "  \($0)" }.joined(separator: "\n")
            }
            let reserved = ["true", "false", "null", "yes", "no", "on", "off", "~"]
            let ambiguous = reserved.contains(s.lowercased())
                || Double(s) != nil
                || s.first == " " || s.last == " "
                || s.contains(": ") || s.hasSuffix(":")
                || "#-?*&!|>%@`\"'".contains(s.first!)
            return ambiguous ? "\"\(s.replacingOccurrences(of: "\"", with: "\\\""))\"" : s
        default: return "\(v)"
        }
    }

    // MARK: - 解析（YAML → JSON）

    private struct Line {
        let no: Int
        let indent: Int
        let text: String
    }

    static func parse(_ source: String) throws -> Any {
        var lines: [Line] = []
        for (i, raw) in source.components(separatedBy: .newlines).enumerated() {
            if raw.hasPrefix("---") || raw.hasPrefix("...") {
                if lines.isEmpty { continue }   // 允许开头的文档分隔符
                throw Unsupported(line: i + 1, reason: "不支持多文档（--- 分隔）")
            }
            let stripped = stripComment(raw)
            if stripped.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            if stripped.contains(" &") || stripped.trimmingCharacters(in: .whitespaces).hasPrefix("*") {
                throw Unsupported(line: i + 1, reason: "不支持锚点 / 别名（& 与 *）")
            }
            let indent = stripped.prefix(while: { $0 == " " }).count
            lines.append(Line(no: i + 1, indent: indent,
                              text: String(stripped.dropFirst(indent))))
        }
        guard !lines.isEmpty else { return [String: Any]() }
        var i = 0
        return try parseBlock(lines, &i, lines[0].indent)
    }

    private static func stripComment(_ s: String) -> String {
        var out = ""
        var inSingle = false, inDouble = false
        for c in s {
            if c == "'" && !inDouble { inSingle.toggle() }
            if c == "\"" && !inSingle { inDouble.toggle() }
            if c == "#" && !inSingle && !inDouble {
                // 只有前面是空白时才算注释起点
                if out.isEmpty || out.last == " " { break }
            }
            out.append(c)
        }
        return out
    }

    private static func parseBlock(_ lines: [Line], _ i: inout Int, _ indent: Int) throws -> Any {
        guard i < lines.count else { return NSNull() }

        if lines[i].text.hasPrefix("- ") || lines[i].text == "-" {
            var arr: [Any] = []
            while i < lines.count, lines[i].indent == indent,
                  lines[i].text.hasPrefix("- ") || lines[i].text == "-" {
                let body = lines[i].text == "-" ? "" : String(lines[i].text.dropFirst(2))
                if body.isEmpty {
                    i += 1
                    if i < lines.count, lines[i].indent > indent {
                        arr.append(try parseBlock(lines, &i, lines[i].indent))
                    } else {
                        arr.append(NSNull())
                    }
                } else if let colon = splitKey(body) {
                    // "- key: value" —— 序列项本身是个映射，它的缩进按 "- " 之后算
                    let virtualIndent = indent + 2
                    var sub: [String: Any] = [:]
                    try readPair(colon, body: body, into: &sub, lines: lines, i: &i,
                                 indent: virtualIndent, firstInline: true)
                    while i < lines.count, lines[i].indent == virtualIndent,
                          !lines[i].text.hasPrefix("- ") {
                        guard let c2 = splitKey(lines[i].text) else {
                            throw Unsupported(line: lines[i].no, reason: "期望 key: value")
                        }
                        try readPair(c2, body: lines[i].text, into: &sub, lines: lines, i: &i,
                                     indent: virtualIndent, firstInline: false)
                    }
                    arr.append(sub)
                } else {
                    arr.append(scalarValue(body))
                    i += 1
                }
            }
            return arr
        }

        var dict: [String: Any] = [:]
        while i < lines.count, lines[i].indent == indent {
            guard let colon = splitKey(lines[i].text) else {
                throw Unsupported(line: lines[i].no,
                                  reason: "无法识别的行「\(lines[i].text)」（只支持 key: value 与 - item）")
            }
            try readPair(colon, body: lines[i].text, into: &dict, lines: lines, i: &i,
                         indent: indent, firstInline: false)
        }
        return dict
    }

    /// 处理一条 `key: value`，value 为空时向下读子块
    private static func readPair(_ colon: Int, body: String, into dict: inout [String: Any],
                                 lines: [Line], i: inout Int, indent: Int,
                                 firstInline: Bool) throws {
        let key = unquote(String(body.prefix(colon)).trimmingCharacters(in: .whitespaces))
        let rest = String(body.dropFirst(colon + 1)).trimmingCharacters(in: .whitespaces)
        i += 1

        if rest.isEmpty {
            if i < lines.count, lines[i].indent > indent {
                dict[key] = try parseBlock(lines, &i, lines[i].indent)
            } else if i < lines.count, lines[i].indent == indent,
                      lines[i].text.hasPrefix("- ") {
                // 序列可以与父键同缩进
                dict[key] = try parseBlock(lines, &i, indent)
            } else {
                dict[key] = NSNull()
            }
        } else if rest == "|" || rest == ">" || rest == "|-" || rest == ">-" {
            var buf: [String] = []
            let base = i < lines.count ? lines[i].indent : indent
            while i < lines.count, lines[i].indent >= base, lines[i].indent > indent {
                buf.append(String(repeating: " ", count: lines[i].indent - base) + lines[i].text)
                i += 1
            }
            let joined = rest.hasPrefix("|") ? buf.joined(separator: "\n")
                                             : buf.joined(separator: " ")
            dict[key] = rest.hasSuffix("-") ? joined
                                            : (joined.isEmpty ? joined : joined + "\n")
        } else {
            dict[key] = scalarValue(rest)
        }
    }

    /// 找到分隔键值的冒号（跳过引号内和 `://`）
    private static func splitKey(_ s: String) -> Int? {
        var inSingle = false, inDouble = false
        let chars = Array(s)
        for (i, c) in chars.enumerated() {
            if c == "'" && !inDouble { inSingle.toggle() }
            if c == "\"" && !inSingle { inDouble.toggle() }
            if c == ":" && !inSingle && !inDouble {
                let next = i + 1 < chars.count ? chars[i + 1] : " "
                if next == " " || i == chars.count - 1 { return i }
            }
        }
        return nil
    }

    private static func unquote(_ s: String) -> String {
        if s.count >= 2, (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            return String(s.dropFirst().dropLast())
        }
        return s
    }

    private static func scalarValue(_ raw: String) -> Any {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.count >= 2, (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            return unquote(s)
        }
        // 内联集合：[a, b] 和 {a: 1}
        if s.hasPrefix("["), s.hasSuffix("]") {
            let inner = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            if inner.isEmpty { return [Any]() }
            return inner.components(separatedBy: ",").map { scalarValue($0) }
        }
        if s.hasPrefix("{"), s.hasSuffix("}") {
            let inner = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            if inner.isEmpty { return [String: Any]() }
            var d: [String: Any] = [:]
            for pair in inner.components(separatedBy: ",") {
                guard let c = splitKey(pair) else { continue }
                d[unquote(String(pair.prefix(c)).trimmingCharacters(in: .whitespaces))] =
                    scalarValue(String(pair.dropFirst(c + 1)))
            }
            return d
        }
        switch s.lowercased() {
        case "true", "yes", "on":   return true
        case "false", "no", "off":  return false
        case "null", "~", "":       return NSNull()
        default: break
        }
        if let i = Int(s) { return i }
        if let d = Double(s) { return d }
        return s
    }
}
