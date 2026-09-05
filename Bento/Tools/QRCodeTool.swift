import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision
import UniformTypeIdentifiers

struct QRCodeTool: ToolView {
    static let meta = ToolMeta(
        id: "qrcode", name: "二维码", category: .image, layout: .canvas,
        symbol: "qrcode",
        aliases: ["qr", "qrcode", "barcode", "ewm", "erweima"]
    )

    enum Mode: Hashable { case generate, scan }

    /// 纠错级别越高，能被遮挡的比例越大，但同样内容需要更多模块
    enum Correction: String, Hashable, CaseIterable {
        case L, M, Q, H
        var label: String { rawValue }
        var tolerance: String {
            switch self {
            case .L: return "≈7%"
            case .M: return "≈15%"
            case .Q: return "≈25%"
            case .H: return "≈30%"
            }
        }
    }

    @State private var mode: Mode = .generate
    @State private var text = "https://github.com"
    @State private var correction: Correction = .M
    @State private var scale: Double = 8
    @State private var fgHex = "#000000"
    @State private var bgHex = "#FFFFFF"

    @State private var scanImage: CGImage?
    @State private var scanInfo: ImageKit.Info?
    @State private var scanResults: [String] = []
    @State private var scanURL: URL?

    init() {}

    var body: some View {
        StackLayout(status: status) {
            BentoSegments(options: [(Mode.generate, "生成"), (.scan, "识别")],
                          selection: $mode, accent: true)
            if mode == .generate {
                OptionLabel(text: "纠错")
                BentoSegments(options: Correction.allCases.map { ($0, $0.label) },
                              selection: $correction)
                OptionLabel(text: "倍率")
                Slider(value: $scale, in: 4...20, step: 1).frame(width: 100)
                Text("\(Int(scale))×").font(Tokens.mono).monospacedDigit().frame(width: 30)
            }
            Spacer()
            if mode == .generate {
                Button("导出 PNG…") { export() }
                    .bentoButton(prominent: true)
                    .disabled(generated == nil)
            }
        } content: {
            if mode == .generate {
                Card {
                    HStack(alignment: .top, spacing: 20) {
                        qrPreview
                        VStack(alignment: .leading, spacing: 12) {
                            CodeArea(text: $text, placeholder: "输入网址或任意文本…")
                                .frame(height: 92)
                                .sunkenSurface(radius: 8)
                            HStack(spacing: 20) {
                                ColorField(label: "前景", hex: $fgHex, size: 28)
                                ColorField(label: "背景", hex: $bgHex, size: 28)
                            }
                        }
                    }
                    .padding(Tokens.padCard)
                }
                .fixedSize(horizontal: false, vertical: true)

                Card(title: "信息", dot: ToolCategory.image.tint, meta: "\(text.utf8.count) 字节") {
                    ResultRows(rows: generateRows, keyWidth: 118)
                        .frame(maxHeight: .infinity)
                }
            } else {
                Card {
                    ImageDropZone(onLoad: loadScan, fileName: scanURL?.lastPathComponent,
                                  info: scanInfo, preview: scanImage)
                }
                .fixedSize(horizontal: false, vertical: true)

                Card(title: "识别结果", dot: ToolCategory.image.tint,
                     meta: scanResults.isEmpty ? "—" : "\(scanResults.count) 个") {
                    if scanResults.isEmpty {
                        Text(scanImage == nil ? "拖入含二维码 / 条形码的图片"
                                              : "没有识别到任何码 · Vision 支持 QR、Aztec、Code128、EAN 等")
                            .font(Tokens.body).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ResultRows(rows: scanResults.enumerated().map { ("#\($0.offset + 1)", $0.element) },
                                   keyWidth: 50)
                            .frame(maxHeight: .infinity)
                    }
                }
            }
        }
    }

    // MARK: - 生成

    private var qrPreview: some View {
        Group {
            if let img = generated {
                Image(decorative: img, scale: 1)
                    .interpolation(.none)          // 二维码放大必须关插值，否则边缘发糊扫不出
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Text("内容为空").font(Tokens.small).foregroundStyle(.tertiary)
            }
        }
        .frame(width: 190, height: 190)
        .sunkenSurface()
    }

    private var generated: CGImage? {
        guard !text.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = correction.rawValue
        guard var ci = filter.outputImage else { return nil }

        if let fg = ColorMath.parse(fgHex), let bg = ColorMath.parse(bgHex) {
            let color = CIFilter.falseColor()
            color.inputImage = ci
            color.color0 = CIColor(red: fg.r, green: fg.g, blue: fg.b)   // 深色模块
            color.color1 = CIColor(red: bg.r, green: bg.g, blue: bg.b)   // 浅色底
            if let out = color.outputImage { ci = out }
        }
        ci = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return CIContext().createCGImage(ci, from: ci.extent)
    }

    private var generateRows: [(String, String)] {
        guard let img = generated else { return [] }
        let modules = Int(Double(img.width) / scale)
        let fg = ColorMath.parse(fgHex) ?? ColorMath.RGB(r: 0, g: 0, b: 0)
        let bg = ColorMath.parse(bgHex) ?? ColorMath.RGB(r: 1, g: 1, b: 1)
        let contrast = ColorMath.contrast(fg, bg)
        return [
            ("输出尺寸", "\(img.width) × \(img.height) px"),
            ("模块数", "\(modules) × \(modules)（version \(max(1, (modules - 17) / 4))）"),
            ("纠错级别", "\(correction.rawValue) · 可容忍 \(correction.tolerance) 面积损坏"),
            ("内容长度", "\(text.count) 字符 / \(text.utf8.count) 字节"),
            ("前景背景对比", String(format: "%.1f:1 %@", contrast,
                                contrast >= 3 ? "✓ 可靠" : "⚠︎ 偏低，扫码器可能识别失败")),
        ]
    }

    private func export() {
        guard let img = generated,
              let data = ImageKit.encode(img, to: .png, stripMetadata: true) else { return }
        ImageExport.save(data, suggested: "qrcode.png", type: .png)
    }

    // MARK: - 识别（Vision）

    private func loadScan(_ url: URL?, _ data: Data) {
        scanURL = url
        scanInfo = ImageKit.info(from: data)
        scanImage = ImageKit.image(from: data)
        scanResults = []
        guard let cg = scanImage else { return }

        let request = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try? handler.perform([request])
        scanResults = (request.results ?? []).compactMap { obs in
            guard let payload = obs.payloadStringValue else { return nil }
            return "\(obs.symbology.rawValue.replacingOccurrences(of: "VNBarcodeSymbology", with: ""))  ·  \(payload)"
        }
    }

    // MARK: -

    private var status: StatusLine {
        if mode == .generate {
            if text.isEmpty {
                return StatusLine(level: .idle, text: "输入内容后生成", trailing: "CoreImage", trailingKey: "⌄")
            }
            guard generated != nil else {
                return StatusLine(level: .error, text: "生成失败 · 内容可能超出二维码容量上限",
                                  trailing: "CoreImage", trailingKey: "⌄")
            }
            let fg = ColorMath.parse(fgHex) ?? ColorMath.RGB(r: 0, g: 0, b: 0)
            let bg = ColorMath.parse(bgHex) ?? ColorMath.RGB(r: 1, g: 1, b: 1)
            if ColorMath.contrast(fg, bg) < 3 {
                return StatusLine(level: .warning,
                                  text: "前景背景对比度不足 3:1，很多扫码器会识别失败",
                                  trailing: "CoreImage", trailingKey: "⌄")
            }
            return StatusLine(level: .ok,
                              text: "已生成 · 纠错 \(correction.rawValue)（可容忍 \(correction.tolerance) 损坏）",
                              trailing: "CoreImage", trailingKey: "⌄")
        } else {
            if scanImage == nil {
                return StatusLine(level: .idle, text: "拖入图片识别", trailing: "Vision", trailingKey: "⌄")
            }
            return scanResults.isEmpty
                ? StatusLine(level: .warning, text: "没有识别到码", trailing: "Vision", trailingKey: "⌄")
                : StatusLine(level: .ok, text: "识别到 \(scanResults.count) 个码",
                             trailing: "Vision", trailingKey: "⌄")
        }
    }
}
