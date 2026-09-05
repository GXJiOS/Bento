import AppIntents
import Foundation
import CryptoKit

/// 快捷指令动作。定义好之后，这些会出现在「快捷指令」App、Spotlight 和
/// `shortcuts run` 命令里，可以和别的自动化串起来。
///
/// 每个 Intent 都是纯计算，不碰 UI，所以不需要把 App 拉起来。

struct Base64EncodeIntent: AppIntent {
    static var title: LocalizedStringResource = "Base64 编码"
    static var description = IntentDescription("把文本编码成 Base64")

    @Parameter(title: "文本") var text: String
    @Parameter(title: "URL-safe", default: false) var urlSafe: Bool

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        var s = Data(text.utf8).base64EncodedString()
        if urlSafe {
            s = s.replacingOccurrences(of: "+", with: "-")
                 .replacingOccurrences(of: "/", with: "_")
                 .replacingOccurrences(of: "=", with: "")
        }
        return .result(value: s)
    }
}

struct Base64DecodeIntent: AppIntent {
    static var title: LocalizedStringResource = "Base64 解码"
    static var description = IntentDescription("把 Base64 还原成文本")

    @Parameter(title: "Base64") var text: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        var t = text.filter { !$0.isWhitespace }
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        t += String(repeating: "=", count: (4 - t.count % 4) % 4)
        guard let d = Data(base64Encoded: t, options: [.ignoreUnknownCharacters]), !d.isEmpty,
              let s = String(data: d, encoding: .utf8), !s.isEmpty else {
            throw $text.needsValueError("这段内容不是有效的 Base64")
        }
        return .result(value: s)
    }
}

struct FormatJSONIntent: AppIntent {
    static var title: LocalizedStringResource = "格式化 JSON"
    static var description = IntentDescription("缩进并可选排序键")

    @Parameter(title: "JSON") var text: String
    @Parameter(title: "排序键", default: false) var sortKeys: Bool

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { throw $text.needsValueError("不是合法 JSON") }
        var opts: JSONSerialization.WritingOptions =
            [.prettyPrinted, .withoutEscapingSlashes, .fragmentsAllowed]
        if sortKeys { opts.insert(.sortedKeys) }
        guard let out = try? JSONSerialization.data(withJSONObject: obj, options: opts),
              let s = String(data: out, encoding: .utf8) else {
            throw $text.needsValueError("序列化失败")
        }
        return .result(value: s)
    }
}

struct HashIntent: AppIntent {
    static var title: LocalizedStringResource = "计算哈希"
    static var description = IntentDescription("MD5 / SHA-1 / SHA-256 / SHA-512")

    enum Algo: String, AppEnum {
        case md5, sha1, sha256, sha512
        static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "算法")
        static var caseDisplayRepresentations: [Algo: DisplayRepresentation] = [
            .md5: "MD5", .sha1: "SHA-1", .sha256: "SHA-256", .sha512: "SHA-512",
        ]
    }

    @Parameter(title: "文本") var text: String
    @Parameter(title: "算法", default: .sha256) var algo: Algo

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let d = Data(text.utf8)
        func hex<H: Sequence>(_ s: H) -> String where H.Element == UInt8 {
            s.map { String(format: "%02x", $0) }.joined()
        }
        let out: String
        switch algo {
        case .md5:    out = hex(Insecure.MD5.hash(data: d))
        case .sha1:   out = hex(Insecure.SHA1.hash(data: d))
        case .sha256: out = hex(SHA256.hash(data: d))
        case .sha512: out = hex(SHA512.hash(data: d))
        }
        return .result(value: out)
    }
}

struct GenerateUUIDIntent: AppIntent {
    static var title: LocalizedStringResource = "生成 UUID"
    static var description = IntentDescription("v4 随机，或 v7 时间有序")

    @Parameter(title: "数量", default: 1, inclusiveRange: (1, 100)) var count: Int
    @Parameter(title: "使用 v7（时间有序）", default: false) var useV7: Bool

    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        let list = (0..<count).map { _ -> String in
            guard useV7 else { return UUID().uuidString.lowercased() }
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
        return .result(value: list)
    }
}

struct DetectContentIntent: AppIntent {
    static var title: LocalizedStringResource = "识别内容类型"
    static var description = IntentDescription("判断是时间戳 / 颜色 / JSON / JWT / Base64 并直接给出解读")

    @Parameter(title: "文本") var text: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let hit = ContentDetector.detect(text) else {
            return .result(value: "未识别")
        }
        return .result(value: "[\(hit.kindLabel)] \(hit.value)\n\(hit.detail)")
    }
}

/// 让上面这些动作出现在快捷指令 App 的建议里
struct BentoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: DetectContentIntent(),
                    phrases: ["用 \(.applicationName) 识别内容"],
                    shortTitle: "识别内容",
                    systemImageName: "wand.and.stars")
        AppShortcut(intent: Base64EncodeIntent(),
                    phrases: ["用 \(.applicationName) 编码 Base64"],
                    shortTitle: "Base64 编码",
                    systemImageName: "arrow.left.arrow.right")
        AppShortcut(intent: FormatJSONIntent(),
                    phrases: ["用 \(.applicationName) 格式化 JSON"],
                    shortTitle: "格式化 JSON",
                    systemImageName: "curlybraces")
    }
}
