import SwiftUI
import UniformTypeIdentifiers

struct IconTool: ToolView {
    static let meta = ToolMeta(
        id: "iconset", name: "图标切图套件", category: .image, layout: .canvas,
        symbol: "app.badge",
        aliases: ["icon", "appicon", "favicon", "icns", "td", "tubiao", "qietu"]
    )

    @State private var sourceData: Data?
    @State private var sourceURL: URL?
    @State private var info: ImageKit.Info?
    @State private var cgImage: CGImage?

    @State private var targets: Set<IconSet.Target> = [.iosModern, .macOS]
    @State private var makeICNS = true
    @State private var makeICO = true
    @State private var appName = "Bento"
    @State private var lastExport: String?
    @State private var icnsError: String?

    init() {}

    var body: some View {
        StackLayout(status: status) {
            OptionLabel(text: "平台")
            ForEach(IconSet.Target.allCases, id: \.self) { t in
                Button(t.label) { toggle(t) }
                    .bentoButton(prominent: targets.contains(t))
                    .help(t.note)
            }
            Spacer()
            Button("导出全部…") { export() }
                .bentoButton(prominent: true)
                .disabled(cgImage == nil || targets.isEmpty)
        } content: {
            Card {
                ImageDropZone(onLoad: load, fileName: sourceURL?.lastPathComponent,
                              info: info, preview: cgImage)
            }
            .fixedSize(horizontal: false, vertical: true)

            if cgImage != nil {
                Card(title: "附加产物", dot: ToolCategory.image.tint, meta: extrasSummary) {
                    HStack(spacing: 16) {
                        BentoCheck(label: ".icns（macOS 应用图标）", isOn: $makeICNS)
                        BentoCheck(label: ".ico（Windows / favicon）", isOn: $makeICO)
                        Divider().frame(height: 20)
                        Text("应用名").font(.system(size: 12)).foregroundStyle(.secondary)
                        TextField("Bento", text: $appName)
                            .textFieldStyle(.plain)
                            .font(Tokens.mono)
                            .padding(.horizontal, 8)
                            .frame(width: 110, height: 26)
                            .sunkenSurface(radius: 6)
                        Spacer()
                    }
                    .padding(.horizontal, Tokens.padCard)
                    .padding(.bottom, Tokens.padCard)
                }
                .fixedSize(horizontal: false, vertical: true)

                Card(title: "将要生成", dot: ToolCategory.formatting.tint,
                     meta: "\(allSpecs.count) 个文件") {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(allSpecs.enumerated()), id: \.offset) { _, item in
                                HStack(spacing: 12) {
                                    Text(item.0)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 96, alignment: .leading)
                                    Text(item.1.filename)
                                        .font(Tokens.mono)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("\(item.1.size)×\(item.1.size)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                    if item.1.size > (info?.pixelWidth ?? 0) {
                                        Text("放大")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(Tokens.warning)
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(Tokens.warning.opacity(0.16),
                                                        in: .rect(cornerRadius: 4))
                                    }
                                }
                                .padding(.horizontal, Tokens.padCard)
                                .frame(height: 24)
                                .overlay(alignment: .top) {
                                    Rectangle().fill(Tokens.separator).frame(height: 0.5)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
            }
        }
    }

    // MARK: -

    private func toggle(_ t: IconSet.Target) {
        if targets.contains(t) { targets.remove(t) } else { targets.insert(t) }
    }

    private func load(_ url: URL?, _ data: Data) {
        sourceURL = url
        sourceData = data
        info = ImageKit.info(from: data)
        cgImage = ImageKit.image(from: data)
        lastExport = nil
    }

    private var allSpecs: [(String, IconSet.Spec)] {
        IconSet.Target.allCases
            .filter { targets.contains($0) }
            .flatMap { t in IconSet.specs(for: t).map { (t.label, $0) } }
    }

    private var extrasSummary: String {
        var parts: [String] = []
        if makeICNS { parts.append(".icns \(IconSet.iconsetTable.count) 档（iconutil）") }
        if makeICO { parts.append(".ico \(IconSet.icoSizes.count) 档") }
        return parts.isEmpty ? "无" : parts.joined(separator: " · ")
    }

    // MARK: - 导出

    private func export() {
        guard let cgImage, let root = ImageExport.saveDirectory("导出图标到此目录") else { return }
        icnsError = nil
        let base = root.appendingPathComponent("\(appName)-icons", isDirectory: true)
        var written = 0

        for target in IconSet.Target.allCases where targets.contains(target) {
            let dir = base.appendingPathComponent(target.folder, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            for spec in IconSet.specs(for: target) {
                let file = dir.appendingPathComponent(spec.filename)
                try? FileManager.default.createDirectory(
                    at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard let scaled = ImageKit.resize(cgImage, to: CGSize(width: spec.size,
                                                                       height: spec.size)),
                      let data = ImageKit.encode(scaled, to: .png, stripMetadata: true)
                else { continue }
                try? data.write(to: file)
                written += 1
            }

            if let json = IconSet.contentsJSON(for: target) {
                try? json.write(to: dir.appendingPathComponent("Contents.json"),
                                atomically: true, encoding: .utf8)
                written += 1
            }
            if target == .favicon {
                try? IconSet.webManifest(appName: appName)
                    .write(to: dir.appendingPathComponent("site.webmanifest"),
                           atomically: true, encoding: .utf8)
                try? IconSet.faviconHTML()
                    .write(to: dir.appendingPathComponent("snippet.html"),
                           atomically: true, encoding: .utf8)
                written += 2
            }
        }

        // .icns 走系统 iconutil：ImageIO 会丢掉 64 和 1024 两档
        if makeICNS {
            switch IconSet.makeICNS(from: cgImage, named: appName, in: base) {
            case .success:            written += 1
            case .failure(let error): icnsError = error.localizedDescription
            }
        }
        if makeICO, let data = multiSize(cgImage, sizes: IconSet.icoSizes,
                                         type: UTType("com.microsoft.ico")) {
            try? data.write(to: base.appendingPathComponent("favicon.ico"))
            written += 1
        }

        lastExport = "\(written) 个文件 → \(base.path)"
        NSWorkspace.shared.activateFileViewerSelecting([base])
    }

    /// 一个容器里塞多个尺寸
    private func multiSize(_ image: CGImage, sizes: [Int], type: UTType?) -> Data? {
        guard let type, ImageKit.canWrite(type) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out as CFMutableData, type.identifier as CFString, sizes.count, nil) else { return nil }
        for s in sizes {
            guard let scaled = ImageKit.resize(image, to: CGSize(width: s, height: s)) else { continue }
            CGImageDestinationAddImage(dest, scaled, nil)
        }
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    private var status: StatusLine {
        guard let info else {
            return StatusLine(level: .idle, text: "拖入一张方形图，建议 1024×1024 PNG",
                              trailing: "ImageIO", trailingKey: "⌄")
        }
        if let err = icnsError {
            return StatusLine(level: .error, text: ".icns 生成失败 · \(err)",
                              trailing: "iconutil", trailingKey: "⌄")
        }
        if let last = lastExport {
            return StatusLine(level: .ok, text: "已导出 \(last)", trailing: "ImageIO", trailingKey: "⌄")
        }
        if info.pixelWidth != info.pixelHeight {
            return StatusLine(level: .warning,
                              text: "源图不是正方形（\(info.pixelWidth)×\(info.pixelHeight)），切出来会被拉伸",
                              trailing: "ImageIO", trailingKey: "⌄")
        }
        if info.pixelWidth < 1024 {
            return StatusLine(level: .warning,
                              text: "源图只有 \(info.pixelWidth)px，1024 档会放大变糊",
                              trailing: "ImageIO", trailingKey: "⌄")
        }
        return StatusLine(level: .ok,
                          text: "\(allSpecs.count) 个尺寸 · \(extrasSummary) · 导出后自动在访达中显示",
                          trailing: "ImageIO", trailingKey: "⌄")
    }
}
