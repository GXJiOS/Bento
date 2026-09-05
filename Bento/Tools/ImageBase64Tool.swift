import SwiftUI
import UniformTypeIdentifiers

struct ImageBase64Tool: ToolView {
    static let meta = ToolMeta(
        id: "imgbase64", name: "图片 ⇄ Base64", category: .image, layout: .dual,
        symbol: "photo.on.rectangle.angled",
        aliases: ["imgbase64", "dataurl", "b64img", "tpb64"]
    )

    enum Mode: Hashable { case toBase64, toImage }
    enum Wrapper: Hashable, CaseIterable {
        case raw, dataURL, cssURL, swiftUI

        var label: String {
            switch self {
            case .raw: return "纯 Base64"
            case .dataURL: return "Data URL"
            case .cssURL: return "CSS url()"
            case .swiftUI: return "SwiftUI"
            }
        }
    }

    @State private var mode: Mode = .toBase64
    @State private var sourceData: Data?
    @State private var sourceURL: URL?
    @State private var info: ImageKit.Info?
    @State private var cgImage: CGImage?
    @State private var wrapper: Wrapper = .dataURL
    @State private var pastedText = ""

    init() {}

    var body: some View {
        StackLayout(status: status) {
            OptionLabel(text: "方向")
            BentoSegments(options: [(Mode.toBase64, "图片 → Base64"), (.toImage, "Base64 → 图片")],
                          selection: $mode, accent: true)
            if mode == .toBase64 {
                OptionLabel(text: "包装")
                BentoSegments(options: Wrapper.allCases.map { ($0, $0.label) }, selection: $wrapper)
            }
            Spacer()
            if mode == .toBase64 {
                CopyButton(value: encodedText, compact: false)
            } else {
                Button("保存图片…") { saveDecoded() }
                    .bentoButton(prominent: true)
                    .disabled(decodedImage == nil)
            }
        } content: {
            if mode == .toBase64 {
                Card {
                    ImageDropZone(onLoad: load, fileName: sourceURL?.lastPathComponent,
                                  info: info, preview: cgImage)
                }
                .fixedSize(horizontal: false, vertical: true)

                Card(title: "输出", dot: ToolCategory.image.tint, meta: sizeSummary) {
                    CodeArea(text: .constant(encodedText), isEditable: false,
                             placeholder: "载入图片后这里出现编码结果")
                }
            } else {
                Card(title: "Base64 / Data URL", dot: ToolCategory.encoding.tint,
                     meta: "\(pastedText.count) 字符") {
                    CodeArea(text: $pastedText, placeholder: "粘贴 Base64 或 data:image/... ")
                        .frame(height: 140)
                }
                .fixedSize(horizontal: false, vertical: true)

                Card(title: "预览", dot: ToolCategory.style.tint, meta: decodedSummary) {
                    decodedPreview
                }
            }
        }
    }

    // MARK: - 编码

    private func load(_ url: URL?, _ data: Data) {
        sourceURL = url
        sourceData = data
        info = ImageKit.info(from: data)
        cgImage = ImageKit.image(from: data)
    }

    private var base64: String { sourceData?.base64EncodedString() ?? "" }

    private var mimeType: String {
        info?.utType?.preferredMIMEType ?? "image/png"
    }

    private var encodedText: String {
        guard !base64.isEmpty else { return "" }
        switch wrapper {
        case .raw:     return base64
        case .dataURL: return "data:\(mimeType);base64,\(base64)"
        case .cssURL:  return "background-image: url(\"data:\(mimeType);base64,\(base64)\");"
        case .swiftUI:
            return """
            // Base64 太长时更建议放进 Assets，这里适合小图标
            let data = Data(base64Encoded: "\(base64.prefix(48))…")!
            Image(nsImage: NSImage(data: data)!)
            """
        }
    }

    private var sizeSummary: String {
        guard let raw = sourceData?.count, raw > 0 else { return "—" }
        let encoded = encodedText.count
        return "\(ImageKit.byteString(raw)) → \(ImageKit.byteString(encoded))"
            + String(format: "（+%.0f%%）", Double(encoded - raw) / Double(raw) * 100)
    }

    // MARK: - 解码

    private var decodedData: Data? {
        var s = pastedText.trimmed
        guard !s.isEmpty else { return nil }
        // 容忍 data URL 前缀、CSS url() 包装和换行
        if let range = s.range(of: "base64,") { s = String(s[range.upperBound...]) }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"');) \n\t"))
        s = s.filter { !$0.isWhitespace }
        return Data(base64Encoded: s, options: [.ignoreUnknownCharacters])
    }

    private var decodedImage: CGImage? {
        decodedData.flatMap { ImageKit.image(from: $0) }
    }

    private var decodedInfo: ImageKit.Info? {
        decodedData.flatMap { ImageKit.info(from: $0) }
    }

    private var decodedSummary: String {
        guard let i = decodedInfo else { return "—" }
        return "\(i.pixelWidth)×\(i.pixelHeight) · \(i.utType?.preferredFilenameExtension?.uppercased() ?? "?") · \(ImageKit.byteString(i.byteCount))"
    }

    @ViewBuilder
    private var decodedPreview: some View {
        if let img = decodedImage {
            Image(decorative: img, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(Tokens.padCard)
        } else {
            Text(pastedText.trimmed.isEmpty ? "粘贴 Base64 后这里显示预览"
                                            : "无法解码为图片 · 检查是否完整")
                .font(Tokens.body)
                .foregroundStyle(pastedText.trimmed.isEmpty ? .secondary : Tokens.error)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func saveDecoded() {
        guard let data = decodedData, let i = decodedInfo else { return }
        let type = i.utType ?? .png
        ImageExport.save(data, suggested: "decoded.\(type.preferredFilenameExtension ?? "png")",
                         type: type)
    }

    // MARK: -

    private var status: StatusLine {
        if mode == .toBase64 {
            guard let raw = sourceData?.count else {
                return StatusLine(level: .idle, text: "拖入一张图片",
                                  trailing: "Base64", trailingKey: "⌄")
            }
            // 超过 ~8KB 的内联图会显著拖慢 HTML/CSS 解析，值得提醒
            if raw > 8 * 1024 {
                return StatusLine(level: .warning,
                                  text: "原图 \(ImageKit.byteString(raw)) 偏大 · 内联 Base64 会撑大 HTML/CSS 并且无法被浏览器单独缓存",
                                  trailing: "Base64", trailingKey: "⌄")
            }
            return StatusLine(level: .ok, text: sizeSummary, trailing: "Base64", trailingKey: "⌄")
        } else {
            if pastedText.trimmed.isEmpty {
                return StatusLine(level: .idle, text: "粘贴 Base64 或 Data URL",
                                  trailing: "Base64", trailingKey: "⌄")
            }
            guard decodedImage != nil else {
                return StatusLine(level: .error, text: "无法解码 · 不是有效的 Base64 图片数据",
                                  trailing: "Base64", trailingKey: "⌄")
            }
            return StatusLine(level: .ok, text: "解码成功 · \(decodedSummary)",
                              trailing: "Base64", trailingKey: "⌄")
        }
    }
}
