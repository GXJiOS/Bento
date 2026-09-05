import Foundation

/// 本地存储。放 `~/Library/Application Support/Bento/`，纯 JSON —— 出问题能直接
/// 用文本编辑器打开看，也方便手动备份。不用 UserDefaults 是因为工具输入可能很长，
/// 而 UserDefaults 不适合放大块数据。
enum Persistence {

    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Bento", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    enum File: String, CaseIterable {
        case state = "state.json"          // 收藏 / 最近 / 展开 / 隐藏
        case settings = "settings.json"    // 偏好
        case clipboard = "clipboard.json"  // 剪贴板历史（默认不存，隐私）
        case memory = "memory.json"        // 每个工具的上次输入

        var url: URL { Persistence.directory.appendingPathComponent(rawValue) }
        var exists: Bool { FileManager.default.fileExists(atPath: url.path) }
        var byteCount: Int {
            (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        }

        var label: String {
            switch self {
            case .state:     return "界面状态"
            case .settings:  return "偏好设置"
            case .clipboard: return "剪贴板历史"
            case .memory:    return "工具输入记忆"
            }
        }
    }

    static func load<T: Decodable>(_ type: T.Type, from file: File) -> T? {
        guard let data = try? Data(contentsOf: file.url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    @discardableResult
    static func save<T: Encodable>(_ value: T, to file: File) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return false }
        // 原子写：崩溃时不会留下半个文件
        return (try? data.write(to: file.url, options: .atomic)) != nil
    }

    static func delete(_ file: File) {
        try? FileManager.default.removeItem(at: file.url)
    }

    static func deleteAll() {
        File.allCases.forEach { delete($0) }
    }

    static var totalBytes: Int {
        File.allCases.reduce(0) { $0 + $1.byteCount }
    }

    /// 把所有配置打成一个包，便于换机器时搬过去
    static func exportBundle() -> Data? {
        var bundle: [String: String] = [:]
        for file in File.allCases where file.exists {
            if let text = try? String(contentsOf: file.url, encoding: .utf8) {
                bundle[file.rawValue] = text
            }
        }
        bundle["_exportedAt"] = ISO8601DateFormatter().string(from: Date())
        bundle["_version"] = "1"
        return try? JSONSerialization.data(withJSONObject: bundle,
                                           options: [.prettyPrinted, .sortedKeys])
    }

    /// 返回成功导入的文件数
    @discardableResult
    static func importBundle(_ data: Data) -> Int {
        guard let bundle = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return 0 }
        var count = 0
        for file in File.allCases {
            guard let text = bundle[file.rawValue] else { continue }
            if (try? text.write(to: file.url, atomically: true, encoding: .utf8)) != nil {
                count += 1
            }
        }
        return count
    }
}

// MARK: - 工具输入记忆

/// 记住每个工具上次输入了什么。
///
/// 只存一份「当前输入」而不是完整历史 —— 后者听着好但实际很少回头翻，
/// 而且会把敏感内容留在盘上。超长输入直接不存。
@Observable
final class ToolMemory {
    static let shared = ToolMemory()

    private var store: [String: String] = [:]
    private var dirty = false

    /// 超过这个长度不记 —— 一整个文件的内容没必要留在配置里
    static let maxLength = 32_768

    var enabled = true {
        didSet { if !enabled { clear() } }
    }

    private init() {
        store = Persistence.load([String: String].self, from: .memory) ?? [:]
    }

    func value(for key: String) -> String? {
        enabled ? store[key] : nil
    }

    func set(_ value: String, for key: String) {
        guard enabled else { return }
        if value.isEmpty || value.count > Self.maxLength {
            store[key] = nil
        } else {
            store[key] = value
        }
        dirty = true
    }

    func flush() {
        guard dirty else { return }
        Persistence.save(store, to: .memory)
        dirty = false
    }

    func clear() {
        store.removeAll()
        Persistence.delete(.memory)
        dirty = false
    }

    var count: Int { store.count }
    var totalCharacters: Int { store.values.reduce(0) { $0 + $1.count } }
}
