import SwiftUI
import UniformTypeIdentifiers

/// 压缩与格式转换合成一个工具 —— 实际用的时候这两件事总是一起做的
struct ImageConvertTool: ToolView {
    static let meta = ToolMeta(
        id: "imgconvert", name: "图片压缩 / 转换", category: .image, layout: .canvas,
        symbol: "photo.badge.arrow.down",
        aliases: ["compress", "convert", "image", "webp", "heic", "tpys", "yasuo", "gszh"]
    )

    @State private var sourceData: Data?
    @State private var sourceURL: URL?
    @State private var info: ImageKit.Info?
    @State private var cgImage: CGImage?

    @State private var targetIndex = 0
    @State private var quality: Double = 0.8
    @State private var maxEdge: Double = 0        // 0 = 不缩放
    @State private var stripMetadata = true

    init() {}

    private var targetType: UTType {
        let types = ImageKit.exportTypes
        return types.indices.contains(targetIndex) ? types[targetIndex] : .png
    }

    var body: some View {
        StackLayout(status: status) {
            OptionLabel(text: "目标格式")
            Picker("", selection: $targetIndex) {
                ForEach(Array(ImageKit.exportTypes.enumerated()), id: \.offset) { i, t in
                    Text((t.preferredFilenameExtension ?? t.identifier).uppercased()).tag(i)
                }
            }
            .labelsHidden()
            .frame(width: 96)
            if ImageKit.isLossy(targetType) {
                OptionLabel(text: "质量")
                Slider(value: $quality, in: 0.1...1).frame(width: 120)
                Text("\(Int(quality * 100))%").font(Tokens.mono).monospacedDigit().frame(width: 40)
            }
            BentoCheck(label: "去除元数据", isOn: $stripMetadata)
            Spacer()
            Button("导出…") { export() }
                .bentoButton(prominent: true)
                .disabled(encoded == nil)
        } content: {
            Card {
                ImageDropZone(onLoad: load, fileName: sourceURL?.lastPathComponent ?? pastedName,
                              info: info, preview: cgImage)
            }
            .fixedSize(horizontal: false, vertical: true)

            if sourceData != nil {
                Card(title: "缩放", dot: ToolCategory.image.tint, meta: resizeSummary) {
                    HStack(spacing: 12) {
                        Text("最长边").font(.system(size: 12)).foregroundStyle(.secondary)
                        Slider(value: $maxEdge, in: 0...4096, step: 16)
                        Text(maxEdge == 0 ? "原始" : "\(Int(maxEdge)) px")
                            .font(Tokens.mono).monospacedDigit()
                            .frame(width: 70, alignment: .trailing)
                        ForEach([0, 512, 1024, 2048], id: \.self) { v in
                            Button(v == 0 ? "原始" : "\(v)") { maxEdge = Double(v) }
                                .bentoButton(plain: true)
                        }
                    }
                    .padding(.horizontal, Tokens.padCard)
                    .padding(.bottom, Tokens.padCard)
                }
                .fixedSize(horizontal: false, vertical: true)

                Card(title: "对比", dot: ToolCategory.style.tint, meta: compareSummary) {
                    ResultRows(rows: compareRows, keyWidth: 118)
                        .frame(maxHeight: .infinity)
                }
            }
        }
    }

    // MARK: -

    @State private var pastedName: String? = nil

    private func load(_ url: URL?, _ data: Data) {
        sourceURL = url
        pastedName = url == nil ? "剪贴板图片" : nil
        sourceData = data
        info = ImageKit.info(from: data)
        cgImage = ImageKit.image(from: data)
        maxEdge = 0
    }

    /// 缩放 + 编码后的结果
    private var encoded: Data? {
        guard let cgImage else { return nil }
        let scaled = maxEdge > 0 ? (ImageKit.fit(cgImage, maxEdge: Int(maxEdge)) ?? cgImage) : cgImage
        return ImageKit.encode(scaled, to: targetType, quality: quality,
                               stripMetadata: stripMetadata,
                               sourceProperties: info?.properties)
    }

    private var resizeSummary: String {
        guard let info else { return "—" }
        guard maxEdge > 0 else { return "\(info.pixelWidth) × \(info.pixelHeight)（原始）" }
        let longest = max(info.pixelWidth, info.pixelHeight)
        guard longest > Int(maxEdge) else { return "小于目标值，不放大" }
        let s = maxEdge / Double(longest)
        return "\(Int(Double(info.pixelWidth) * s)) × \(Int(Double(info.pixelHeight) * s))"
    }

    private var compareSummary: String {
        guard let before = info?.byteCount, let after = encoded?.count else { return "—" }
        let delta = Double(after - before) / Double(before) * 100
        return String(format: "%@ → %@（%+.1f%%）",
                      ImageKit.byteString(before), ImageKit.byteString(after), delta)
    }

    private var compareRows: [(String, String)] {
        guard let info, let out = encoded else { return [] }
        let ratio = Double(out.count) / Double(info.byteCount)
        let outInfo = ImageKit.info(from: out)
        return [
            ("原始", "\(info.utType?.preferredFilenameExtension?.uppercased() ?? "?")  "
                + "\(info.pixelWidth)×\(info.pixelHeight)  \(ImageKit.byteString(info.byteCount))"),
            ("输出", "\((targetType.preferredFilenameExtension ?? "?").uppercased())  "
                + "\(outInfo?.pixelWidth ?? 0)×\(outInfo?.pixelHeight ?? 0)  \(ImageKit.byteString(out.count))"),
            ("体积变化", String(format: "%.1f%%  （%@）", ratio * 100,
                            out.count < info.byteCount ? "省下 \(ImageKit.byteString(info.byteCount - out.count))"
                                                       : "增大 \(ImageKit.byteString(out.count - info.byteCount))")),
            ("透明通道", (outInfo?.hasAlpha ?? false) ? "保留"
                : (info.hasAlpha ? "⚠︎ 丢失（目标格式不支持）" : "原本就没有")),
            ("元数据", stripMetadata ? "已去除（含 GPS）" : "保留 EXIF / GPS / IPTC"),
        ]
    }

    private func export() {
        guard let data = encoded else { return }
        let base = sourceURL?.deletingPathExtension().lastPathComponent ?? "image"
        let ext = targetType.preferredFilenameExtension ?? "png"
        ImageExport.save(data, suggested: "\(base).\(ext)", type: targetType)
    }

    private var status: StatusLine {
        guard let info else {
            return StatusLine(level: .idle, text: "拖入或选择一张图片",
                              trailing: "ImageIO", trailingKey: "⌄")
        }
        guard let out = encoded else {
            return StatusLine(level: .error, text: "编码失败 · 该格式可能不支持当前色彩模式",
                              trailing: "ImageIO", trailingKey: "⌄")
        }
        // 把「透明丢失」这类静默损失提到状态栏，别让人导完才发现
        if info.hasAlpha, !(ImageKit.info(from: out)?.hasAlpha ?? false) {
            return StatusLine(level: .warning,
                              text: "\((targetType.preferredFilenameExtension ?? "").uppercased()) 不支持透明通道，导出后会变成不透明底",
                              trailing: "ImageIO", trailingKey: "⌄")
        }
        return StatusLine(level: .ok, text: compareSummary, trailing: "ImageIO", trailingKey: "⌄")
    }
}
