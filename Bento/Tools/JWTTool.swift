import SwiftUI

struct JWTTool: ToolView {
    static let meta = ToolMeta(
        id: "jwt", name: "JWT 解析", category: .encoding, layout: .form,
        symbol: "key",
        aliases: ["jwt", "token", "jw", "lp"]
    )

    /// 三段 base64url，就是 split + decode + JSON。不值得为它引一个包。
    struct Parsed {
        var header: String
        var payload: String
        var signature: String
        var claims: [(String, String)]
        var expiry: Date?
        var issuedAt: Date?
    }

    private static let sample = """
        eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6Ikp\
        vaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyLCJleHAiOjE5MDAwMDAwMDB9.SflKxwRJSMeKKF2QT4\
        fwpMeJf36POk6yJV_adQssw5c
        """

    @State private var input = JWTTool.sample

    init() {}

    var body: some View {
        StackLayout(status: status) {
            OptionLabel(text: "签名")
            Text("不验证 · 只解码")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
            Spacer()
            Button("粘贴") {
                input = NSPasteboard.general.string(forType: .string) ?? input
            }.bentoButton()
            Button("示例") { input = Self.sample }.bentoButton(plain: true)
        } content: {
            Card(title: "TOKEN", dot: ToolCategory.encoding.tint, meta: "\(input.count) 字符") {
                CodeArea(text: $input, placeholder: "粘贴 JWT…")
                    .frame(height: 76)
            }
            .fixedSize(horizontal: false, vertical: true)

            if let p = parsed {
                HStack(spacing: Tokens.gapCard) {
                    Card(title: "HEADER", dot: ToolCategory.formatting.tint, meta: "alg / typ") {
                        CodeArea(text: .constant(p.header), isEditable: false)
                    }
                    Card(title: "PAYLOAD", dot: ToolCategory.style.tint,
                         meta: "\(p.claims.count) 个声明") {
                        CodeArea(text: .constant(p.payload), isEditable: false)
                    }
                }

                Card(title: "标准声明", dot: ToolCategory.image.tint, meta: "逐行复制") {
                    ResultRows(rows: p.claims, keyWidth: 132)
                }
                .frame(height: 168)
            } else {
                Card {
                    Text(errorText ?? "等待输入")
                        .font(Tokens.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(Tokens.padCard)
                }
            }
        }
    }

    // MARK: - 解析

    private var parsed: Parsed? {
        let token = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: "")
        guard !token.isEmpty else { return nil }
        let parts = token.components(separatedBy: ".")
        guard parts.count == 3,
              let hData = Self.base64url(parts[0]),
              let pData = Self.base64url(parts[1]),
              let header = Self.pretty(hData),
              let payload = Self.pretty(pData),
              let obj = try? JSONSerialization.jsonObject(with: pData) as? [String: Any]
        else { return nil }

        let hObj = (try? JSONSerialization.jsonObject(with: hData)) as? [String: Any] ?? [:]

        var rows: [(String, String)] = []
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"

        func timeRow(_ key: String, _ label: String) -> Date? {
            guard let v = obj[key] as? Double else { return nil }
            let d = Date(timeIntervalSince1970: v)
            rows.append((label, "\(Int(v))  ·  \(df.string(from: d))"))
            return d
        }

        if let alg = hObj["alg"] as? String { rows.append(("alg 算法", alg)) }
        if let typ = hObj["typ"] as? String { rows.append(("typ 类型", typ)) }
        if let kid = hObj["kid"] as? String { rows.append(("kid 密钥 ID", kid)) }
        for (key, label) in [("iss", "iss 签发方"), ("sub", "sub 主体"), ("aud", "aud 受众"),
                             ("jti", "jti 唯一 ID")] {
            if let v = obj[key] { rows.append((label, "\(v)")) }
        }
        let issued = timeRow("iat", "iat 签发时间")
        _ = timeRow("nbf", "nbf 生效时间")
        let exp = timeRow("exp", "exp 过期时间")

        if let exp {
            let left = exp.timeIntervalSinceNow
            rows.append((
                "有效期",
                left > 0 ? "剩余 \(Self.duration(left))" : "已过期 \(Self.duration(-left))"
            ))
        }

        return Parsed(header: header, payload: payload, signature: parts[2],
                      claims: rows, expiry: exp, issuedAt: issued)
    }

    private var errorText: String? {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let parts = t.components(separatedBy: ".")
        if parts.count != 3 { return "不是有效的 JWT · 应为 3 段 base64url（当前 \(parts.count) 段）" }
        if Self.base64url(parts[0]) == nil { return "header 段不是合法的 base64url" }
        if Self.base64url(parts[1]) == nil { return "payload 段不是合法的 base64url" }
        return "payload 不是合法 JSON"
    }

    private var status: StatusLine {
        guard let p = parsed else {
            return input.trimmingCharacters(in: .whitespaces).isEmpty
                ? StatusLine(level: .idle, text: "等待输入", trailing: "RFC 7519", trailingKey: "⌄")
                : StatusLine(level: .error, text: errorText ?? "解析失败",
                             trailing: "RFC 7519", trailingKey: "⌄")
        }
        if let exp = p.expiry, exp < Date() {
            return StatusLine(level: .error,
                              text: "已过期 \(Self.duration(-exp.timeIntervalSinceNow)) · 签名未验证",
                              trailing: "RFC 7519", trailingKey: "⌄")
        }
        return StatusLine(level: .ok,
                          text: "解析成功 · \(p.claims.count) 个声明 · 签名未验证",
                          trailing: "RFC 7519", trailingKey: "⌄")
    }

    // MARK: - Helper

    private static func base64url(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+")
                 .replacingOccurrences(of: "_", with: "/")
        t += String(repeating: "=", count: (4 - t.count % 4) % 4)
        return Data(base64Encoded: t)
    }

    private static func pretty(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let out = try? JSONSerialization.data(
                withJSONObject: obj,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return nil }
        return String(data: out, encoding: .utf8)
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(abs(seconds))
        if s < 60 { return "\(s) 秒" }
        if s < 3600 { return "\(s / 60) 分钟" }
        if s < 86400 { return "\(s / 3600) 小时" }
        return "\(s / 86400) 天"
    }
}
