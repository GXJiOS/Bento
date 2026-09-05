import Foundation
import CryptoKit
import AppKit

/// CLI 伴生模式。
///
/// App 的主二进制同时也是命令行工具：`BentoMain.main()` 在启动 SwiftUI 之前
/// 先问一句 `runIfNeeded()`，命中就处理完直接 `exit`，UI 一次都不会建。
///
/// 装一个 wrapper 到 PATH 上就能用：
/// ```
/// echo '{"a":1}' | bento json
/// bento b64 hello
/// bento ts 1735689600
/// ```
enum CLIRunner {

    static let commands: [(name: String, usage: String, help: String)] = [
        ("detect",  "bento detect <文本>",       "自动识别内容类型"),
        ("b64",     "bento b64 [-d] <文本>",     "Base64 编码 / 解码"),
        ("url",     "bento url [-d] <文本>",     "URL 百分号编码 / 解码"),
        ("json",    "bento json [-c] <JSON>",    "格式化 / 压缩（-c）"),
        ("hash",    "bento hash [算法] <文本>",   "md5 / sha1 / sha256（默认）/ sha512"),
        ("uuid",    "bento uuid [个数] [-7]",     "生成 UUID，-7 用时间有序的 v7"),
        ("ts",      "bento ts [时间戳]",          "时间戳 ⇄ 日期，省略参数给当前时间"),
        ("case",    "bento case <风格> <文本>",   "camel / pascal / snake / kebab / const"),
    ]

    /// 返回 true 表示已按 CLI 处理完毕，调用方不要再启动 UI
    static func runIfNeeded() -> Bool {
        var args = Array(CommandLine.arguments.dropFirst())
        // Xcode 调试启动会塞 -NSDocumentRevisionsDebugMode 之类的参数，别误判成 CLI
        args.removeAll { $0.hasPrefix("-NS") || $0 == "YES" || $0 == "NO" }
        guard let command = args.first else { return false }

        let isHelp = ["-h", "--help", "help"].contains(command)
        let isKnown = commands.contains(where: { $0.name == command })
        // 第一个参数不以 - 开头 = 用户在终端敲的命令。这种情况下命令拼错要报错，
        // 不能默默启动 GUI（在终端里那看起来就像卡住了）。
        if !isKnown && !isHelp {
            guard command.hasPrefix("-") else {
                FileHandle.standardError.write(Data("""
                bento: 未知命令「\(command)」

                \(helpText)

                """.utf8))
                exit(1)
            }
            return false
        }

        let rest = Array(args.dropFirst())
        let output: String

        switch command {
        case "-h", "--help", "help":
            output = helpText
        case "detect":
            let text = input(rest)
            if let hit = ContentDetector.detect(text) {
                output = "[\(hit.kindLabel)] \(hit.value)\n\(hit.detail)"
            } else {
                output = "未识别"
            }
        case "b64":
            let decode = rest.contains("-d")
            let text = input(rest.filter { $0 != "-d" })
            if decode {
                var t = text.filter { !$0.isWhitespace }
                t += String(repeating: "=", count: (4 - t.count % 4) % 4)
                // .ignoreUnknownCharacters 会把非法字符直接滤掉，
                // 结果为空说明输入根本不是 Base64，不能当成功
                guard let d = Data(base64Encoded: t, options: [.ignoreUnknownCharacters]),
                      !d.isEmpty, let s = String(data: d, encoding: .utf8), !s.isEmpty else {
                    return fail("无效的 Base64")
                }
                output = s
            } else {
                output = Data(text.utf8).base64EncodedString()
            }
        case "url":
            let decode = rest.contains("-d")
            let text = input(rest.filter { $0 != "-d" })
            if decode {
                guard let s = text.removingPercentEncoding else { return fail("无效的百分号编码") }
                output = s
            } else {
                let allowed = CharacterSet(charactersIn:
                    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
                output = text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
            }
        case "json":
            let compact = rest.contains("-c")
            let text = input(rest.filter { $0 != "-c" })
            guard let data = text.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data,
                                                              options: [.fragmentsAllowed])
            else { return fail("不是合法 JSON") }
            var opts: JSONSerialization.WritingOptions = [.withoutEscapingSlashes, .fragmentsAllowed]
            if !compact { opts.insert(.prettyPrinted) }
            guard let out = try? JSONSerialization.data(withJSONObject: obj, options: opts),
                  let s = String(data: out, encoding: .utf8) else { return fail("序列化失败") }
            output = s
        case "hash":
            let algos = ["md5", "sha1", "sha256", "sha512"]
            let algo = rest.first.map { algos.contains($0) ? $0 : "sha256" } ?? "sha256"
            let text = input(algos.contains(rest.first ?? "") ? Array(rest.dropFirst()) : rest)
            let d = Data(text.utf8)
            switch algo {
            case "md5":    output = hex(Insecure.MD5.hash(data: d))
            case "sha1":   output = hex(Insecure.SHA1.hash(data: d))
            case "sha512": output = hex(SHA512.hash(data: d))
            default:       output = hex(SHA256.hash(data: d))
            }
        case "uuid":
            let n = rest.compactMap { Int($0) }.first ?? 1
            let v7 = rest.contains("-7")
            output = (0..<max(1, min(n, 1000))).map { _ in
                v7 ? uuidV7() : UUID().uuidString.lowercased()
            }.joined(separator: "\n")
        case "ts":
            let text = rest.first ?? input(rest)
            if text.isEmpty {
                output = "\(Int(Date().timeIntervalSince1970))"
            } else if let n = Double(text) {
                let date = Date(timeIntervalSince1970: text.count >= 12 ? n / 1000 : n)
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
                output = f.string(from: date)
            } else {
                return fail("无法解析：\(text)")
            }
        case "case":
            guard let styleName = rest.first else { return fail("需要指定风格") }
            let map: [String: CaseTool.Style] = [
                "camel": .camel, "pascal": .pascal, "snake": .snake,
                "kebab": .kebab, "const": .constant, "dot": .dot,
            ]
            guard let style = map[styleName] else {
                return fail("未知风格 \(styleName)，可用：\(map.keys.sorted().joined(separator: " / "))")
            }
            output = input(Array(rest.dropFirst()))
                .components(separatedBy: .newlines)
                .filter { !$0.trimmed.isEmpty }
                .map { CaseTool.convert($0.trimmed, to: style) }
                .joined(separator: "\n")
        default:
            output = helpText
        }

        print(output)
        exit(0)
    }

    // MARK: - Helper

    /// 优先用参数；没有参数就从 stdin 读（支持管道）
    private static func input(_ args: [String]) -> String {
        if !args.isEmpty { return args.joined(separator: " ") }
        guard let data = try? FileHandle.standardInput.readToEnd(),
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s.trimmingCharacters(in: .newlines)
    }

    private static func fail(_ message: String) -> Bool {
        FileHandle.standardError.write(Data(("bento: " + message + "\n").utf8))
        exit(1)
    }

    private static func hex<H: Sequence>(_ d: H) -> String where H.Element == UInt8 {
        d.map { String(format: "%02x", $0) }.joined()
    }

    private static func uuidV7() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let ms = UInt64(Date().timeIntervalSince1970 * 1000)
        for i in 0..<6 { bytes[i] = UInt8((ms >> (8 * (5 - UInt64(i)))) & 0xFF) }
        for i in 6..<16 { bytes[i] = UInt8.random(in: 0...255) }
        bytes[6] = (bytes[6] & 0x0F) | 0x70
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let h = bytes.map { String(format: "%02x", $0) }.joined()
        return [h.prefix(8), h.dropFirst(8).prefix(4), h.dropFirst(12).prefix(4),
                h.dropFirst(16).prefix(4), h.dropFirst(20)].joined(separator: "-")
    }

    static var helpText: String {
        var lines = ["bento — Bento.app 的命令行伴生工具", ""]
        for c in commands {
            lines.append("  \(c.usage.padding(toLength: 30, withPad: " ", startingAt: 0))\(c.help)")
        }
        lines.append("")
        lines.append("不带参数时从 stdin 读，可以接管道：echo '{\"a\":1}' | bento json")
        return lines.joined(separator: "\n")
    }

    // MARK: - 安装

    static var wrapperPath: URL {
        URL(fileURLWithPath: "/usr/local/bin/bento")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: wrapperPath.path)
    }

    static var script: String {
        let exe = Bundle.main.executableURL?.path ?? "/Applications/Bento.app/Contents/MacOS/Bento"
        return "#!/bin/sh\nexec \"\(exe)\" \"$@\"\n"
    }

    /// /usr/local/bin 不一定可写（没装过 Homebrew 的机器上是 root:wheel），
    /// 失败时把手动命令回给调用方，别只说一句「失败了」
    enum InstallError: LocalizedError {
        case notWritable(String)
        var errorDescription: String? {
            if case .notWritable(let cmd) = self {
                return "/usr/local/bin 不可写，请在终端手动执行：\n\(cmd)"
            }
            return nil
        }
    }

    static func install() -> Result<String, InstallError> {
        let dir = wrapperPath.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
            catch { return .failure(.notWritable(manualCommand)) }
        }
        do {
            try script.write(to: wrapperPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                  ofItemAtPath: wrapperPath.path)
            return .success(wrapperPath.path)
        } catch {
            return .failure(.notWritable(manualCommand))
        }
    }

    static var manualCommand: String {
        let exe = Bundle.main.executableURL?.path ?? ""
        return "sudo mkdir -p /usr/local/bin && "
             + "printf '#!/bin/sh\\nexec \"\(exe)\" \"$@\"\\n' | sudo tee /usr/local/bin/bento >/dev/null && "
             + "sudo chmod +x /usr/local/bin/bento"
    }

    static func uninstall() {
        try? FileManager.default.removeItem(at: wrapperPath)
    }
}
