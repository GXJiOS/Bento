import Foundation

/// 响应头分析：安全头、缓存策略、压缩、Cookie。
/// 纯字符串逻辑，可脱离 App 直接验证。
enum HeaderAnalyzer {

    enum Level {
        case good, warn, bad, info
    }

    struct Finding {
        let level: Level
        let title: String
        let detail: String
    }

    struct Report {
        var security: [Finding] = []
        var caching: [Finding] = []
        var general: [Finding] = []

        var score: Int {
            let all = security
            guard !all.isEmpty else { return 0 }
            let good = all.filter { $0.level == .good }.count
            return Int(Double(good) / Double(all.count) * 100)
        }
    }

    /// 解析粘贴进来的原始响应头文本（curl -I 的输出直接能用）
    static func parse(_ raw: String) -> [(String, String)] {
        raw.components(separatedBy: .newlines).compactMap { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !t.hasPrefix("HTTP/"), let colon = t.firstIndex(of: ":") else {
                return nil
            }
            return (String(t[t.startIndex..<colon]).trimmingCharacters(in: .whitespaces),
                    String(t[t.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
        }
    }

    static func analyze(_ headers: [(String, String)]) -> Report {
        var report = Report()
        let map = Dictionary(headers.map { ($0.0.lowercased(), $0.1) },
                             uniquingKeysWith: { a, b in a + ", " + b })

        // MARK: 安全头
        func check(_ key: String, _ title: String, missing: String,
                   validate: (String) -> Finding?) {
            guard let value = map[key] else {
                report.security.append(Finding(level: .warn, title: title, detail: missing))
                return
            }
            report.security.append(validate(value)
                ?? Finding(level: .good, title: title, detail: value))
        }

        check("strict-transport-security", "HSTS",
              missing: "缺失 —— 浏览器仍可能走一次明文 HTTP") { v in
            let maxAge = maxAgeValue(v) ?? 0
            if maxAge < 15_552_000 {   // 半年，提交 HSTS preload 的门槛
                return Finding(level: .warn, title: "HSTS",
                               detail: "max-age=\(maxAge) 偏短，建议 ≥ 15552000（半年）")
            }
            return nil
        }

        check("content-security-policy", "CSP",
              missing: "缺失 —— XSS 防护少一层") { v in
            if v.contains("unsafe-inline") || v.contains("unsafe-eval") {
                return Finding(level: .warn, title: "CSP",
                               detail: "含 unsafe-inline / unsafe-eval，防护效果打折")
            }
            return nil
        }

        check("x-content-type-options", "X-Content-Type-Options",
              missing: "缺失 —— 浏览器会做 MIME 嗅探") { v in
            v.lowercased() == "nosniff" ? nil
                : Finding(level: .warn, title: "X-Content-Type-Options",
                          detail: "值应为 nosniff，当前是 \(v)")
        }

        check("x-frame-options", "X-Frame-Options",
              missing: "缺失 —— 可能被嵌进 iframe 做点击劫持（CSP frame-ancestors 也可代替）") { v in
            ["deny", "sameorigin"].contains(v.lowercased()) ? nil
                : Finding(level: .warn, title: "X-Frame-Options", detail: "值可疑：\(v)")
        }

        check("referrer-policy", "Referrer-Policy",
              missing: "缺失 —— 跳转时可能泄露完整 URL") { _ in nil }

        if let server = map["server"] {
            report.security.append(Finding(
                level: server.contains(where: \.isNumber) ? .warn : .info,
                title: "Server",
                detail: server.contains(where: \.isNumber)
                    ? "\(server) —— 暴露了版本号，建议隐藏" : server))
        }
        for leak in ["x-powered-by", "x-aspnet-version", "x-generator"] {
            if let v = map[leak] {
                report.security.append(Finding(level: .warn, title: leak,
                                               detail: "\(v) —— 暴露技术栈，建议移除"))
            }
        }

        // MARK: 缓存
        if let cc = map["cache-control"] {
            let lower = cc.lowercased()
            var notes: [String] = []
            if lower.contains("no-store") { notes.append("完全不缓存") }
            else if lower.contains("no-cache") { notes.append("每次都要回源校验") }
            if let maxAge = maxAgeValue(cc) {
                notes.append("有效期 \(humanDuration(maxAge))")
            }
            if lower.contains("immutable") { notes.append("immutable（适合带 hash 的静态资源）") }
            if lower.contains("public") { notes.append("允许 CDN 缓存") }
            if lower.contains("private") { notes.append("只允许浏览器缓存") }
            report.caching.append(Finding(level: .good, title: "Cache-Control",
                                          detail: notes.isEmpty ? cc : notes.joined(separator: " · ")))
        } else {
            report.caching.append(Finding(level: .warn, title: "Cache-Control",
                                          detail: "缺失 —— 缓存行为交给浏览器猜，不可预期"))
        }
        if map["etag"] != nil || map["last-modified"] != nil {
            report.caching.append(Finding(level: .good, title: "校验",
                                          detail: [map["etag"].map { "ETag \($0)" },
                                                   map["last-modified"].map { "Last-Modified \($0)" }]
                                            .compactMap { $0 }.joined(separator: " · ")))
        } else {
            report.caching.append(Finding(level: .info, title: "校验",
                                          detail: "没有 ETag / Last-Modified，无法做 304 协商缓存"))
        }
        if let vary = map["vary"] {
            report.caching.append(Finding(level: .info, title: "Vary", detail: vary))
        }

        // MARK: 常规
        if let ct = map["content-type"] {
            let hasCharset = ct.lowercased().contains("charset")
            report.general.append(Finding(
                level: hasCharset || !ct.contains("text") ? .good : .warn,
                title: "Content-Type",
                detail: hasCharset || !ct.contains("text") ? ct : "\(ct) —— 文本类型建议带 charset"))
        }
        if let enc = map["content-encoding"] {
            report.general.append(Finding(level: .good, title: "压缩", detail: enc))
        } else {
            report.general.append(Finding(level: .warn, title: "压缩",
                                          detail: "没有 Content-Encoding —— 文本资源建议开 gzip / br"))
        }
        if let len = map["content-length"], let n = Int(len) {
            report.general.append(Finding(level: .info, title: "Content-Length",
                                          detail: "\(n) 字节（\(ImageKit.byteString(n))）"))
        }
        if let cookie = map["set-cookie"] {
            let lower = cookie.lowercased()
            var missing: [String] = []
            if !lower.contains("httponly") { missing.append("HttpOnly") }
            if !lower.contains("secure") { missing.append("Secure") }
            if !lower.contains("samesite") { missing.append("SameSite") }
            report.general.append(Finding(
                level: missing.isEmpty ? .good : .bad,
                title: "Set-Cookie",
                detail: missing.isEmpty ? "HttpOnly / Secure / SameSite 齐全"
                                        : "缺少 \(missing.joined(separator: "、"))"))
        }
        if let alt = map["alt-svc"] {
            report.general.append(Finding(level: .info, title: "Alt-Svc",
                                          detail: "\(alt)（支持 HTTP/3 时会出现）"))
        }
        return report
    }

    /// 从 `max-age=3600; ...` 里取出那个数。
    /// 注意别写成 `.prefix{}.flatMap{}` —— 那是逐字符 map，得到的是 [Int] 不是一个数。
    static func maxAgeValue(_ value: String) -> Int? {
        guard let tail = value.lowercased()
            .components(separatedBy: "max-age=").dropFirst().first else { return nil }
        let digits = tail.prefix { $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }

    static func humanDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) 秒" }
        if seconds < 3600 { return "\(seconds / 60) 分钟" }
        if seconds < 86400 { return "\(seconds / 3600) 小时" }
        return "\(seconds / 86400) 天"
    }
}
