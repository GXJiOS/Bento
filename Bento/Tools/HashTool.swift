import SwiftUI
import CryptoKit
import UniformTypeIdentifiers

struct HashTool: ToolView {
    static let meta = ToolMeta(
        id: "hash", name: "哈希计算", category: .encoding, layout: .form,
        symbol: "number.circle",
        aliases: ["hash", "md5", "sha", "sha256", "crc", "hx", "haxi"]
    )

    enum Source: Hashable { case text, file }

    @State private var input = "Hello, 世界 🌍"
    @State private var source: Source = .text
    @State private var uppercase = false
    @State private var fileURL: URL?
    @State private var fileData: Data?
    @State private var dropTargeted = false

    init() {}

    var body: some View {
        StackLayout(status: status) {
            OptionLabel(text: "输入")
            BentoSegments(options: [(Source.text, "文本"), (.file, "文件")], selection: $source)
            BentoCheck(label: "大写", isOn: $uppercase)
            Spacer()
            if source == .file {
                Button("选择文件…") { pickFile() }.bentoButton(prominent: true)
            }
        } content: {
            if source == .text {
                Card(title: "INPUT", dot: ToolCategory.encoding.tint,
                     meta: "\(data.count) 字节") {
                    CodeArea(text: $input, placeholder: "在此输入或粘贴…")
                        .frame(height: 108)
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                fileCard
            }

            Card(title: "摘要", dot: ToolCategory.image.tint, meta: "6 种 · 逐行复制") {
                ResultRows(rows: rows, keyWidth: 108)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: - 文件

    private var fileCard: some View {
        Card {
            VStack(spacing: 8) {
                Image(systemName: fileURL == nil ? "arrow.down.doc" : "doc.text.fill")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(dropTargeted ? Tokens.accent : Color.secondary)
                if let url = fileURL {
                    Text(url.lastPathComponent).font(Tokens.body)
                    Text("\(Self.byteSize(fileData?.count ?? 0)) · \(url.path)")
                        .font(Tokens.small).foregroundStyle(.tertiary).lineLimit(1)
                } else {
                    Text("把文件拖到这里，或点上方「选择文件…」")
                        .font(Tokens.body).foregroundStyle(.secondary)
                    Text("非沙盒，可直接读任意路径")
                        .font(Tokens.small).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(dropTargeted ? Tokens.accent.opacity(0.07) : Color.clear)
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                _ = providers.first?.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { load(url) }
                }
                return true
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { load(url) }
    }

    private func load(_ url: URL) {
        fileURL = url
        fileData = try? Data(contentsOf: url)
    }

    // MARK: - 计算

    private var data: Data {
        source == .text ? Data(input.utf8) : (fileData ?? Data())
    }

    private var rows: [(String, String)] {
        guard !data.isEmpty else { return [] }
        let d = data
        return [
            ("MD5", hex(Insecure.MD5.hash(data: d))),
            ("SHA-1", hex(Insecure.SHA1.hash(data: d))),
            ("SHA-256", hex(SHA256.hash(data: d))),
            ("SHA-384", hex(SHA384.hash(data: d))),
            ("SHA-512", hex(SHA512.hash(data: d))),
            ("CRC32", cased(String(format: "%08x", Self.crc32(d)))),
        ]
    }

    private func hex<H: Sequence>(_ digest: H) -> String where H.Element == UInt8 {
        cased(digest.map { String(format: "%02x", $0) }.joined())
    }

    private func cased(_ s: String) -> String { uppercase ? s.uppercased() : s }

    /// CryptoKit 不提供 CRC32（它不是密码学哈希），表驱动自己算
    private static func crc32(_ data: Data) -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1 == 1) ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1) }
            table[i] = c
        }
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static func byteSize(_ n: Int) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: Int64(n))
    }

    private var status: StatusLine {
        if data.isEmpty {
            return StatusLine(level: .idle,
                              text: source == .text ? "等待输入" : "等待选择文件",
                              trailing: "CryptoKit", trailingKey: "⌄")
        }
        let warn = source == .text && input.isEmpty
        return StatusLine(
            level: warn ? .warning : .ok,
            text: "已计算 · \(Self.byteSize(data.count)) · MD5/SHA-1 仅用于校验，勿用于安全场景",
            trailing: "CryptoKit", trailingKey: "⌄"
        )
    }
}
