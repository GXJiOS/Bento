import SwiftUI
import UniformTypeIdentifiers

struct ExifTool: ToolView {
    static let meta = ToolMeta(
        id: "exif", name: "EXIF 查看", category: .image, layout: .form,
        symbol: "camera.metering.matrix",
        aliases: ["exif", "metadata", "gps", "yssj", "yuanshuju"]
    )

    @State private var sourceData: Data?
    @State private var sourceURL: URL?
    @State private var info: ImageKit.Info?
    @State private var cgImage: CGImage?
    @State private var cleanedNote: String?

    init() {}

    var body: some View {
        StackLayout(status: status) {
            OptionLabel(text: "元数据")
            Text("EXIF · TIFF · GPS · IPTC")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
            Spacer()
            Button("导出无元数据副本…") { exportClean() }
                .bentoButton(prominent: hasSensitive)
                .disabled(cgImage == nil)
                .help("重新编码一份不带 EXIF / GPS 的图片")
        } content: {
            Card {
                ImageDropZone(onLoad: load, fileName: sourceURL?.lastPathComponent,
                              info: info, preview: cgImage)
            }
            .fixedSize(horizontal: false, vertical: true)

            if let info {
                Card(title: "基本信息", dot: ToolCategory.image.tint, meta: "总览") {
                    ResultRows(rows: basicRows(info), keyWidth: 118)
                }
                .fixedSize(horizontal: false, vertical: true)

                let groups = ImageKit.metadata(from: info.properties)
                if groups.isEmpty {
                    Card {
                        Text("这张图不含 EXIF / GPS / IPTC —— 可能已被处理过，或本来就是程序生成的")
                            .font(Tokens.body).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Tokens.padCard)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(groups, id: \.title) { g in
                        Card(title: g.title,
                             dot: g.title.hasPrefix("GPS") ? Tokens.warning : ToolCategory.style.tint,
                             meta: "\(g.rows.count) 项") {
                            ResultRows(rows: g.rows, keyWidth: 150)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: -

    private func load(_ url: URL?, _ data: Data) {
        sourceURL = url
        sourceData = data
        info = ImageKit.info(from: data)
        cgImage = ImageKit.image(from: data)
        cleanedNote = nil
    }

    private func basicRows(_ info: ImageKit.Info) -> [(String, String)] {
        [
            ("尺寸", "\(info.pixelWidth) × \(info.pixelHeight) px  ·  \(info.aspect)  ·  "
                + String(format: "%.2f MP", info.megapixels)),
            ("格式", (info.utType?.preferredFilenameExtension?.uppercased() ?? "?")
                + "  ·  \(info.utType?.identifier ?? "")"),
            ("文件大小", ImageKit.byteString(info.byteCount)),
            ("色彩", "\(info.colorModel)  ·  \(info.depth) bit/通道"
                + (info.hasAlpha ? "  ·  含 Alpha" : "")),
            ("分辨率", String(format: "%.0f DPI", info.dpi)),
            ("帧数", info.isAnimated ? "\(info.frameCount) 帧（动图）" : "1"),
        ]
    }

    private var hasSensitive: Bool {
        guard let info else { return false }
        return ImageKit.hasGPS(info.properties)
    }

    private func exportClean() {
        guard let cgImage, let info else { return }
        let type = info.utType.flatMap { ImageKit.canWrite($0) ? $0 : nil } ?? .png
        guard let data = ImageKit.encode(cgImage, to: type, quality: 0.92,
                                         stripMetadata: true) else { return }
        let base = sourceURL?.deletingPathExtension().lastPathComponent ?? "image"
        let ext = type.preferredFilenameExtension ?? "png"
        ImageExport.save(data, suggested: "\(base)-clean.\(ext)", type: type)
    }

    private var status: StatusLine {
        guard let info else {
            return StatusLine(level: .idle, text: "拖入一张图片查看元数据",
                              trailing: "ImageIO", trailingKey: "⌄")
        }
        if ImageKit.hasGPS(info.properties) {
            return StatusLine(level: .warning,
                              text: "⚠︎ 这张图带 GPS 定位信息 — 直接发出去会暴露拍摄地点",
                              trailing: "ImageIO", trailingKey: "⌄")
        }
        let count = ImageKit.metadata(from: info.properties).reduce(0) { $0 + $1.rows.count }
        return StatusLine(level: .ok, text: "\(count) 项元数据 · 无 GPS",
                          trailing: "ImageIO", trailingKey: "⌄")
    }
}
