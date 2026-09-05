import Foundation

/// 内容类型识别。命令面板的 inline 直出、剪贴板监听、菜单栏面板共用同一套。
///
/// 纯 Foundation，不含任何 UI 类型（颜色以 hex 字符串返回，由 View 层转换），
/// 所以能脱离 App 直接跑验证。
enum ContentDetector {

    enum Kind: String {
        case jwt, timestamp, color, json, url, expression, base64

        var label: String {
            switch self {
            case .jwt:        return "JWT"
            case .timestamp:  return "时间戳"
            case .color:      return "颜色"
            case .json:       return "JSON"
            case .url:        return "URL"
            case .expression: return "算式"
            case .base64:     return "Base64"
            }
        }
    }

    struct Hit {
        var kind: Kind
        var symbol: String            // SF Symbol 名
        var value: String             // 直出结果，⌘C 拿走的就是它
        var detail: String
        /// 相关工具的名字，第一个是「直接打开」
        var relatedToolNames: [String]
        var swatchHex: String?

        var kindLabel: String { kind.label }
    }

    // MARK: - 入口

    /// 顺序有讲究：JWT 必须排在 Base64 前面（它每一段都是 base64url），
    /// JSON 必须排在 Base64 前面（`{"a":1}` 不是 base64 但短 JSON 可能误判）。
    static func detect(_ raw: String) -> Hit? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count < 100_000 else { return nil }

        return jwt(text)
            ?? timestamp(text)
            ?? color(text)
            ?? json(text)
            ?? url(text)
            ?? expression(text)
            ?? base64(text)
    }

    // MARK: - 各类型

    private static func jwt(_ s: String) -> Hit? {
        let parts = s.components(separatedBy: ".")
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty }),
              let payload = base64urlDecode(parts[1]),
              let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
        else { return nil }

        var detail = "\(obj.count) 个声明"
        if let exp = obj["exp"] as? Double {
            let date = Date(timeIntervalSince1970: exp)
            detail += date < Date() ? " · 已过期" : " · 有效至 \(shortDate(date))"
        }
        let subject = (obj["sub"] as? String) ?? (obj["name"] as? String) ?? ""
        return Hit(kind: .jwt, symbol: "key",
                   value: subject.isEmpty ? "\(obj.count) claims" : subject,
                   detail: detail,
                   relatedToolNames: ["JWT 解析", "Base64 编解码", "JSON 工具箱"])
    }

    private static func timestamp(_ s: String) -> Hit? {
        guard s.allSatisfy(\.isNumber), s.count == 10 || s.count == 13, let n = Double(s)
        else { return nil }
        let date = Date(timeIntervalSince1970: s.count == 13 ? n / 1000 : n)
        // 1973 年之前 / 2100 年之后的多半不是时间戳，是别的什么数字
        guard date.timeIntervalSince1970 > 100_000_000,
              date.timeIntervalSince1970 < 4_102_444_800 else { return nil }

        let rel = RelativeDateTimeFormatter()
        rel.locale = Locale(identifier: "zh_Hans")
        let week = DateFormatter()
        week.locale = Locale(identifier: "zh_Hans")
        week.dateFormat = "EEEE"
        return Hit(kind: .timestamp, symbol: "clock",
                   value: fullDate(date),
                   detail: "\(week.string(from: date)) · \(rel.localizedString(for: date, relativeTo: Date())) · \(TimeZone.current.identifier)",
                   relatedToolNames: ["时间戳转换", "Cron 解析", "进制转换"])
    }

    private static func color(_ s: String) -> Hit? {
        let hex = s.hasPrefix("#") ? String(s.dropFirst()) : s
        guard hex.count == 6 || hex.count == 8, hex.allSatisfy(\.isHexDigit),
              let c = ColorMath.parse(s) else { return nil }
        let (r, g, b) = c.bytes
        let hsl = ColorMath.toHSL(c)
        let onWhite = ColorMath.contrast(c, ColorMath.RGB(r: 1, g: 1, b: 1))
        return Hit(kind: .color, symbol: "eyedropper",
                   value: "rgb(\(r), \(g), \(b))",
                   detail: "H\(Int(hsl.h)) S\(Int(hsl.s * 100)) L\(Int(hsl.l * 100)) · 对白 "
                         + String(format: "%.1f:1", onWhite)
                         + " · 近 \(ColorMath.nearestTailwind(c).name)",
                   relatedToolNames: ["颜色转换", "对比度检查", "调色板生成"],
                   swatchHex: c.hex)
    }

    private static func json(_ s: String) -> Hit? {
        guard s.hasPrefix("{") || s.hasPrefix("["), s.count > 3,
              let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let summary: String
        if let d = obj as? [String: Any] {
            summary = "\(d.count) 个键：\(d.keys.sorted().prefix(4).joined(separator: ", "))"
                    + (d.count > 4 ? "…" : "")
        } else if let a = obj as? [Any] {
            summary = "\(a.count) 个元素"
        } else {
            return nil
        }
        return Hit(kind: .json, symbol: "curlybraces",
                   value: summary,
                   detail: "\(s.count) 字符 · 合法 JSON",
                   relatedToolNames: ["JSON 工具箱", "JSON → 模型", "JSON Diff"])
    }

    private static func url(_ s: String) -> Hit? {
        guard s.hasPrefix("http://") || s.hasPrefix("https://"),
              let u = URL(string: s), let host = u.host() else { return nil }
        let params = u.query()?.components(separatedBy: "&").count ?? 0
        return Hit(kind: .url, symbol: "link",
                   value: host + u.path(),
                   detail: "\(u.scheme ?? "") · \(params) 个查询参数"
                         + (s.contains("%") ? " · 含百分号编码" : ""),
                   relatedToolNames: ["URL 编解码", "二维码", "HTTP 测试器"])
    }

    private static func expression(_ s: String) -> Hit? {
        guard s.count < 100,
              s.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/")) != nil,
              s.allSatisfy({ $0.isNumber || "+-*/(). ".contains($0) }),
              s.contains(where: \.isNumber) else { return nil }
        // NSExpression 对畸形输入会抛 ObjC 异常，先做一次括号配平检查
        let open = s.filter { $0 == "(" }.count, close = s.filter { $0 == ")" }.count
        guard open == close else { return nil }
        guard let n = NSExpression(format: s).expressionValue(with: nil, context: nil) as? NSNumber
        else { return nil }
        return Hit(kind: .expression, symbol: "equal",
                   value: "\(n)",
                   detail: "算式求值",
                   relatedToolNames: ["进制转换", "单位换算", "间距栅格"])
    }

    private static func base64(_ s: String) -> Hit? {
        guard s.count >= 8, s.count % 4 == 0 || s.hasSuffix("="),
              s.allSatisfy({ $0.isLetter || $0.isNumber || "+/=".contains($0) }),
              let data = Data(base64Encoded: s, options: [.ignoreUnknownCharacters]),
              !data.isEmpty else { return nil }

        // 能解成可读文本才算命中，否则一串普通字母也会被当成 base64
        if let text = String(data: data, encoding: .utf8),
           !text.isEmpty,
           text.allSatisfy({ !$0.isNewline && ($0.isLetter || $0.isNumber
                             || $0.isPunctuation || $0.isWhitespace || $0.isSymbol) }) {
            return Hit(kind: .base64, symbol: "arrow.down.doc",
                       value: text, detail: "Base64 解码 · \(data.count) 字节",
                       relatedToolNames: ["Base64 编解码", "图片 ⇄ Base64", "字符串转义"])
        }
        // 二进制就报告一下是什么
        if let info = ImageKit.info(from: data), info.pixelWidth > 0 {
            return Hit(kind: .base64, symbol: "photo",
                       value: "\(info.pixelWidth)×\(info.pixelHeight) "
                            + (info.utType?.preferredFilenameExtension?.uppercased() ?? "图片"),
                       detail: "Base64 图片 · \(ImageKit.byteString(data.count))",
                       relatedToolNames: ["图片 ⇄ Base64", "图片压缩 / 转换", "EXIF 查看"])
        }
        return nil
    }

    // MARK: - Helper

    static func base64urlDecode(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+")
                 .replacingOccurrences(of: "_", with: "/")
        t += String(repeating: "=", count: (4 - t.count % 4) % 4)
        return Data(base64Encoded: t)
    }

    private static func fullDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: d)
    }

    private static func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}
