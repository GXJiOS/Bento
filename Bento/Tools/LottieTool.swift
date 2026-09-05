import SwiftUI
import UniformTypeIdentifiers

/// Lottie **元信息**查看器。
///
/// 不做播放：渲染 Lottie 需要引 lottie-ios（一个不小的第三方依赖），
/// 而日常真正要回答的问题是「这个动画多长、多少图层、有没有引用外部图片、
/// 体积为什么这么大」—— 这些从 JSON 结构就能读出来。
struct LottieTool: ToolView {
    static let meta = ToolMeta(
        id: "lottie", name: "Lottie 检查", category: .image, layout: .form,
        symbol: "square.stack.3d.down.forward",
        aliases: ["lottie", "animation", "json", "dh", "donghua"]
    )

    struct Report {
        var version = "—"
        var width = 0, height = 0
        var frameRate: Double = 0
        var inPoint: Double = 0
        var outPoint: Double = 0
        var layers: [(type: String, name: String)] = []
        var assetCount = 0
        var imageAssets: [String] = []
        var precompCount = 0
        var hasExpressions = false
        var byteCount = 0

        var duration: Double { frameRate > 0 ? (outPoint - inPoint) / frameRate : 0 }
        var frameCount: Int { Int(outPoint - inPoint) }
    }

    /// Lottie 的 layer type 是数字，对照 bodymovin 的定义
    private static let layerTypes = [
        0: "预合成", 1: "纯色", 2: "图片", 3: "空对象", 4: "形状", 5: "文本",
    ]

    @State private var report: Report?
    @State private var fileName: String?
    @State private var parseError: String?
    @State private var targeted = false

    init() {}

    var body: some View {
        StackLayout(status: status) {
            OptionLabel(text: "说明")
            Text("只读结构与元信息，不做播放渲染")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
                .help("播放需要引入 lottie-ios 依赖；这里回答的是时长/图层/外链资源这类问题")
            Spacer()
            Button("选择 .json…") { pick() }.bentoButton(prominent: report == nil)
        } content: {
            Card {
                HStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Tokens.sunkenBG)
                        .frame(width: 110, height: 110)
                        .overlay(
                            Image(systemName: report == nil ? "square.stack.3d.down.forward"
                                                            : "checkmark.seal")
                                .font(.system(size: 26, weight: .light))
                                .foregroundStyle(targeted ? Tokens.accent
                                                 : (report == nil ? Color.secondary : Tokens.ok))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(targeted ? Tokens.accent : Tokens.separator,
                                              style: StrokeStyle(lineWidth: targeted ? 1.5 : 0.5,
                                                                 dash: report == nil ? [4, 3] : []))
                        )
                    VStack(alignment: .leading, spacing: 5) {
                        if let fileName {
                            Text(fileName).font(.system(size: 13, weight: .medium))
                        } else {
                            Text("把 Lottie 的 .json 拖到这里").font(Tokens.body)
                        }
                        if let e = parseError {
                            Text(e).font(Tokens.small).foregroundStyle(Tokens.error)
                        } else if let r = report {
                            Text(String(format: "%.2f 秒 · %d 帧 · %g fps · %d×%d",
                                        r.duration, r.frameCount, r.frameRate, r.width, r.height))
                                .font(Tokens.small).foregroundStyle(.secondary)
                        } else {
                            Text("bodymovin / After Effects 导出的动画 JSON")
                                .font(Tokens.small).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                }
                .padding(Tokens.padCard)
                .onDrop(of: [.fileURL, .json], isTargeted: $targeted, perform: handleDrop)
            }
            .fixedSize(horizontal: false, vertical: true)

            if let r = report {
                Card(title: "概要", dot: ToolCategory.image.tint, meta: ImageKit.byteString(r.byteCount)) {
                    ResultRows(rows: summaryRows(r), keyWidth: 118)
                }
                .fixedSize(horizontal: false, vertical: true)

                Card(title: "图层", dot: ToolCategory.style.tint, meta: "\(r.layers.count) 个") {
                    ResultRows(rows: r.layers.enumerated().map {
                        ("#\($0.offset + 1)  \($0.element.type)", $0.element.name)
                    }, keyWidth: 118)
                        .frame(maxHeight: .infinity)
                }
            }
        }
    }

    // MARK: -

    private func summaryRows(_ r: Report) -> [(String, String)] {
        var rows: [(String, String)] = [
            ("bodymovin 版本", r.version),
            ("画布", "\(r.width) × \(r.height)"),
            ("时长", String(format: "%.2f 秒（%d 帧 @ %g fps）", r.duration, r.frameCount, r.frameRate)),
            ("图层数", "\(r.layers.count)" + (r.precompCount > 0 ? " · 含 \(r.precompCount) 个预合成" : "")),
            ("资源", r.assetCount == 0 ? "无" : "\(r.assetCount) 项"),
        ]
        if !r.imageAssets.isEmpty {
            rows.append(("⚠︎ 外链图片", r.imageAssets.joined(separator: ", ")
                + " — 这些文件要跟 JSON 一起打包"))
        }
        if r.hasExpressions {
            rows.append(("⚠︎ 表达式", "含 AE 表达式，部分 Lottie 运行时不支持，需在 AE 里烘焙"))
        }
        return rows
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let p = providers.first, p.canLoadObject(ofClass: URL.self) else { return false }
        _ = p.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            DispatchQueue.main.async { load(url) }
        }
        return true
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { load(url) }
    }

    private func load(_ url: URL) {
        fileName = url.lastPathComponent
        parseError = nil
        report = nil
        guard let data = try? Data(contentsOf: url) else {
            parseError = "读不到文件"; return
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            parseError = "不是合法 JSON"; return
        }
        guard obj["layers"] != nil, obj["fr"] != nil else {
            parseError = "缺少 layers / fr 字段 — 这不像 Lottie 动画 JSON"; return
        }

        var r = Report()
        r.byteCount = data.count
        r.version = obj["v"] as? String ?? "—"
        r.width = obj["w"] as? Int ?? 0
        r.height = obj["h"] as? Int ?? 0
        r.frameRate = obj["fr"] as? Double ?? 0
        r.inPoint = obj["ip"] as? Double ?? 0
        r.outPoint = obj["op"] as? Double ?? 0

        if let layers = obj["layers"] as? [[String: Any]] {
            r.layers = layers.map { l in
                let t = l["ty"] as? Int ?? -1
                if t == 0 { r.precompCount += 1 }
                return (Self.layerTypes[t] ?? "类型 \(t)", l["nm"] as? String ?? "（未命名）")
            }
        }
        if let assets = obj["assets"] as? [[String: Any]] {
            r.assetCount = assets.count
            r.imageAssets = assets.compactMap { $0["p"] as? String }.filter { !$0.isEmpty }
        }
        // 表达式藏在属性的 "x" 字段里，全文搜一下最省事
        r.hasExpressions = String(data: data, encoding: .utf8)?.contains("\"x\":\"") ?? false

        report = r
    }

    private var status: StatusLine {
        if let e = parseError {
            return StatusLine(level: .error, text: e, trailing: "bodymovin", trailingKey: "⌄")
        }
        guard let r = report else {
            return StatusLine(level: .idle, text: "拖入 Lottie 的 .json",
                              trailing: "bodymovin", trailingKey: "⌄")
        }
        if !r.imageAssets.isEmpty {
            return StatusLine(level: .warning,
                              text: "含 \(r.imageAssets.count) 个外链图片资源 — 只发 JSON 会缺图",
                              trailing: "bodymovin", trailingKey: "⌄")
        }
        return StatusLine(level: .ok,
                          text: String(format: "%.2f 秒 · %d 图层 · %@ · 自包含",
                                       r.duration, r.layers.count, ImageKit.byteString(r.byteCount)),
                          trailing: "bodymovin", trailingKey: "⌄")
    }
}
