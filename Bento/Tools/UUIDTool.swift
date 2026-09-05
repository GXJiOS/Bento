import SwiftUI

struct UUIDTool: ToolView {
    static let meta = ToolMeta(
        id: "uuid", name: "UUID 生成", category: .encoding, layout: .form,
        symbol: "number.square",
        aliases: ["uuid", "guid", "nanoid", "id", "ulid"]
    )

    enum Version: Hashable, CaseIterable {
        case v4, v7, nano

        var label: String {
            switch self {
            case .v4:   return "UUID v4"
            case .v7:   return "UUID v7"
            case .nano: return "NanoID"
            }
        }

        var note: String {
            switch self {
            case .v4:   return "纯随机 · 最通用"
            case .v7:   return "时间有序 · 建索引友好"
            case .nano: return "21 位短 ID · URL 安全"
            }
        }
    }

    enum Style: Hashable, CaseIterable {
        case standard, upper, compact, braces

        var label: String {
            switch self {
            case .standard: return "标准"
            case .upper:    return "大写"
            case .compact:  return "无连字符"
            case .braces:   return "花括号"
            }
        }
    }

    @State private var version: Version = .v4
    @State private var style: Style = .standard
    @State private var count = 5
    @State private var seed = 0          // 改它就重新生成
    @State private var output = ""

    init() {}

    var body: some View {
        StackLayout(status: status) {
            OptionLabel(text: "类型")
            BentoSegments(options: Version.allCases.map { ($0, $0.label) }, selection: $version)
            OptionLabel(text: "格式")
            BentoSegments(options: Style.allCases.map { ($0, $0.label) }, selection: $style)
            Spacer()
            Button("生成") { seed += 1 }.bentoButton(prominent: true)
        } content: {
            Card {
                HStack(spacing: 14) {
                    Text("数量").font(.system(size: 12)).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { Double(count) },
                                          set: { count = Int($0) }), in: 1...100, step: 1)
                        .frame(width: 240)
                    Text("\(count)")
                        .font(.system(size: 13, design: .monospaced))
                        .monospacedDigit()
                        .frame(width: 34, alignment: .leading)
                    Text(version.note).font(.system(size: 12)).foregroundStyle(.tertiary)
                    Spacer()
                    CopyButton(value: output, compact: false)
                }
                .padding(Tokens.padCard)
            }
            .fixedSize(horizontal: false, vertical: true)

            Card(title: "生成结果", dot: ToolCategory.encoding.tint,
                 meta: "\(lines.count) 条 · \(output.count) 字符") {
                CodeArea(text: .constant(output), isEditable: false)
            }
        }
        .onAppear { regenerate() }
        .onChange(of: seed) { _, _ in regenerate() }
        .onChange(of: count) { _, _ in regenerate() }
        .onChange(of: version) { _, _ in regenerate() }
        .onChange(of: style) { _, _ in regenerate() }
    }

    private var lines: [String] {
        output.isEmpty ? [] : output.components(separatedBy: "\n")
    }

    private func regenerate() {
        output = (0..<count).map { _ in format(generate()) }.joined(separator: "\n")
    }

    private func generate() -> String {
        switch version {
        case .v4:   return UUID().uuidString
        case .v7:   return Self.uuidV7()
        case .nano: return Self.nanoID()
        }
    }

    private func format(_ raw: String) -> String {
        guard version != .nano else { return raw }
        switch style {
        case .standard: return raw.lowercased()
        case .upper:    return raw.uppercased()
        case .compact:  return raw.replacingOccurrences(of: "-", with: "").lowercased()
        case .braces:   return "{\(raw.lowercased())}"
        }
    }

    /// UUID v7：前 48 位是毫秒时间戳，所以按字典序就是按时间序 —— 拿来做主键
    /// 不会像 v4 那样把 B 树索引打散。Foundation 只给 v4，v7 自己拼。
    private static func uuidV7() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let ms = UInt64(Date().timeIntervalSince1970 * 1000)
        for i in 0..<6 { bytes[i] = UInt8((ms >> (8 * (5 - UInt64(i)))) & 0xFF) }
        for i in 6..<16 { bytes[i] = UInt8.random(in: 0...255) }
        bytes[6] = (bytes[6] & 0x0F) | 0x70          // version 7
        bytes[8] = (bytes[8] & 0x3F) | 0x80          // variant RFC 4122
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let parts = [hex.prefix(8),
                     hex.dropFirst(8).prefix(4),
                     hex.dropFirst(12).prefix(4),
                     hex.dropFirst(16).prefix(4),
                     hex.dropFirst(20)]
        return parts.joined(separator: "-")
    }

    private static func nanoID(length: Int = 21) -> String {
        let alphabet = Array("useandom-26T198340PX75pxJACKVERYMINDBUSHWOLF_GQZbfghjklqvwyzrict")
        return String((0..<length).map { _ in alphabet.randomElement()! })
    }

    private var status: StatusLine {
        StatusLine(level: .ok,
                   text: "已生成 \(lines.count) 条 · \(version.label) · \(version.note)",
                   trailing: version == .nano ? "NanoID" : "RFC 4122", trailingKey: "⌄")
    }
}
