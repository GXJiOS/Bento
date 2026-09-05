import SwiftUI
import UniformTypeIdentifiers

/// 图像工具共用的载入区：拖入 / 选择 / 粘贴三种方式。
/// 非沙盒，可以直接读用户拖进来的任意路径。
struct ImageDropZone: View {
    let onLoad: (URL?, Data) -> Void
    var fileName: String?
    var info: ImageKit.Info?
    var preview: CGImage?
    var height: CGFloat = 150

    @State private var targeted = false

    var body: some View {
        HStack(spacing: 16) {
            thumbnail
            if let info, let fileName {
                details(info, fileName)
            } else {
                hint
            }
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                Button("选择文件…") { pick() }.bentoButton(prominent: preview == nil)
                Button("从剪贴板") { pasteFromClipboard() }.bentoButton()
            }
        }
        .padding(Tokens.padCard)
        .frame(maxWidth: .infinity)
        .background(targeted ? Tokens.accent.opacity(0.07) : Color.clear)
        .onDrop(of: [.fileURL, .image], isTargeted: $targeted, perform: handleDrop)
    }

    // MARK: - 片段

    private var thumbnail: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Tokens.sunkenBG)
            .frame(width: height, height: height)
            .overlay {
                if let preview {
                    Image(decorative: preview, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(6)
                } else {
                    Image(systemName: targeted ? "arrow.down.circle" : "photo")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(targeted ? Tokens.accent : Color.secondary)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(targeted ? Tokens.accent : Tokens.separator,
                                  style: StrokeStyle(lineWidth: targeted ? 1.5 : 0.5,
                                                     dash: preview == nil ? [4, 3] : []))
            )
    }

    private var hint: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("把图片拖到这里").font(Tokens.body)
            Text("支持 PNG / JPEG / HEIC / WebP / TIFF / GIF / ICNS 等 ImageIO 能读的全部格式")
                .font(Tokens.small).foregroundStyle(.secondary)
            Text("非沙盒 · 可直接读任意路径").font(Tokens.small).foregroundStyle(.tertiary)
        }
    }

    private func details(_ info: ImageKit.Info, _ name: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(name).font(.system(size: 13, weight: .medium)).lineLimit(1)
            Text("\(info.pixelWidth) × \(info.pixelHeight) px  ·  \(info.aspect)  ·  "
                 + String(format: "%.1f MP", info.megapixels))
                .font(Tokens.small).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                tag(info.utType?.preferredFilenameExtension?.uppercased() ?? "?")
                tag(ImageKit.byteString(info.byteCount))
                if info.hasAlpha { tag("Alpha") }
                if info.isAnimated { tag("\(info.frameCount) 帧") }
                if ImageKit.hasGPS(info.properties) { tag("含 GPS", warning: true) }
            }
        }
    }

    private func tag(_ s: String, warning: Bool = false) -> some View {
        Text(s)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(warning ? Tokens.warning : Color.secondary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background((warning ? Tokens.warning : Color.secondary).opacity(0.15),
                        in: .rect(cornerRadius: 4))
    }

    // MARK: - 载入

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let p = providers.first else { return false }
        if p.canLoadObject(ofClass: URL.self) {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url, let data = try? Data(contentsOf: url) else { return }
                DispatchQueue.main.async { onLoad(url, data) }
            }
            return true
        }
        p.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            guard let data else { return }
            DispatchQueue.main.async { onLoad(nil, data) }
        }
        return true
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url,
           let data = try? Data(contentsOf: url) {
            onLoad(url, data)
        }
    }

    private func pasteFromClipboard() {
        let pb = NSPasteboard.general
        if let data = pb.data(forType: .tiff) ?? pb.data(forType: .png) {
            onLoad(nil, data)
        } else if let s = pb.string(forType: .string),
                  let url = URL(string: s), url.isFileURL,
                  let data = try? Data(contentsOf: url) {
            onLoad(url, data)
        }
    }
}

/// 保存导出结果的通用面板
enum ImageExport {
    static func save(_ data: Data, suggested: String, type: UTType) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggested
        panel.allowedContentTypes = [type]
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    static func saveDirectory(_ prompt: String = "选择导出位置") -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url : nil
    }
}
