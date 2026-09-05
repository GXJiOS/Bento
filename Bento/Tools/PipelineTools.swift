import SwiftUI
import UniformTypeIdentifiers

// MARK: - 工具链

struct PipelineTool: ToolView {
    static let meta = ToolMeta(
        id: "pipeline", name: "工具链", category: .system, layout: .stacked,
        symbol: "arrow.triangle.branch",
        aliases: ["pipeline", "chain", "pipe", "gjl", "gongjulian"]
    )

    @Environment(AppState.self) private var app
    @State private var input = ""
    @State private var steps: [String] = []
    @State private var results: [(tool: String, output: String)] = []

    /// 能进链条的工具：输入输出都是文本的那些
    private static let chainable: [(id: String, name: String, run: (String) -> String?)] = [
        ("base64.encode", "Base64 编码", { Data($0.utf8).base64EncodedString() }),
        ("base64.decode", "Base64 解码", { s in
            var t = s.filter { !$0.isWhitespace }
            t += String(repeating: "=", count: (4 - t.count % 4) % 4)
            guard let d = Data(base64Encoded: t, options: [.ignoreUnknownCharacters]), !d.isEmpty
            else { return nil }
            return String(data: d, encoding: .utf8)
        }),
        ("url.encode", "URL 编码", {
            $0.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn:
                "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"))
        }),
        ("url.decode", "URL 解码", { $0.removingPercentEncoding }),
        ("json.pretty", "JSON 格式化", { s in
            guard let d = s.data(using: .utf8),
                  let o = try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed]),
                  let out = try? JSONSerialization.data(withJSONObject: o,
                        options: [.prettyPrinted, .withoutEscapingSlashes, .fragmentsAllowed])
            else { return nil }
            return String(data: out, encoding: .utf8)
        }),
        ("json.minify", "JSON 压缩", { s in
            guard let d = s.data(using: .utf8),
                  let o = try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed]),
                  let out = try? JSONSerialization.data(withJSONObject: o,
                        options: [.withoutEscapingSlashes, .fragmentsAllowed])
            else { return nil }
            return String(data: out, encoding: .utf8)
        }),
        ("case.snake", "转 snake_case", { s in
            s.components(separatedBy: .newlines)
                .map { $0.trimmed.isEmpty ? "" : CaseTool.convert($0.trimmed, to: .snake) }
                .joined(separator: "\n")
        }),
        ("case.camel", "转 camelCase", { s in
            s.components(separatedBy: .newlines)
                .map { $0.trimmed.isEmpty ? "" : CaseTool.convert($0.trimmed, to: .camel) }
                .joined(separator: "\n")
        }),
        ("trim", "去首尾空白", { $0.trimmed }),
        ("lines.unique", "行去重", { s in
            var seen = Set<String>()
            return s.components(separatedBy: .newlines).filter { seen.insert($0).inserted }
                .joined(separator: "\n")
        }),
        ("lines.sort", "行排序", {
            $0.components(separatedBy: .newlines).sorted().joined(separator: "\n")
        }),
    ]

    init() {}

    var body: some View {
        StackLayout(status: status) {
            OptionLabel(text: "加一步")
            Menu("选择工具") {
                ForEach(Self.chainable, id: \.id) { step in
                    Button(step.name) { steps.append(step.id); run() }
                }
            }
            .frame(width: 110)
            Spacer()
            Button("从剪贴板取输入") {
                input = NSPasteboard.general.string(forType: .string) ?? ""
                run()
            }
            .bentoButton()
            Button("清空链条") { steps = []; run() }
                .bentoButton(plain: true)
                .disabled(steps.isEmpty)
        } content: {
            HStack(spacing: Tokens.gapCard) {
                Card(title: "输入", dot: ToolCategory.encoding.tint, meta: "\(input.count) 字符") {
                    CodeArea(text: $input, placeholder: "粘贴要处理的内容…")
                        .onChange(of: input) { _, _ in run() }
                }
                Card(title: "输出", dot: ToolCategory.image.tint, meta: outputMeta) {
                    CodeArea(text: .constant(finalOutput), isEditable: false)
                    CardFooter {
                        CopyButton(value: finalOutput, compact: false)
                        Spacer()
                        Text("每一步的中间结果见下方")
                            .font(Tokens.small).foregroundStyle(.tertiary)
                    }
                }
            }

            Card(title: "链条", dot: ToolCategory.system.tint, meta: "\(steps.count) 步") {
                if steps.isEmpty {
                    Text("还没有步骤 —— 从左上角「选择工具」加一步。\n"
                         + "典型用法：URL 解码 → JSON 格式化，或 Base64 解码 → JSON 格式化")
                        .font(Tokens.body).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(Tokens.padCard)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(steps.enumerated()), id: \.offset) { i, id in
                                stepRow(i, id)
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
            }
        }
        .onAppear {
            if let pending = app.consumePendingInput() { input = pending; run() }
        }
    }

    private func stepRow(_ index: Int, _ id: String) -> some View {
        let name = Self.chainable.first { $0.id == id }?.name ?? id
        let result = index < results.count ? results[index] : (tool: name, output: "")
        let ok = !result.output.isEmpty
        return HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary).frame(width: 18)
            Circle().fill(ok ? Tokens.ok : Tokens.error).frame(width: 6, height: 6)
            Text(name).font(.system(size: 12)).frame(width: 110, alignment: .leading)
            Text(ok ? String(result.output.prefix(80)).replacingOccurrences(of: "\n", with: "⏎")
                    : "这一步失败了 —— 上一步的输出不是它能处理的格式")
                .font(Tokens.mono)
                .foregroundStyle(ok ? AnyShapeStyle(.secondary) : AnyShapeStyle(Tokens.error))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                steps.remove(at: index); run()
            } label: { Image(systemName: "xmark").font(.system(size: 9)) }
            .bentoButton(plain: true)
        }
        .padding(.horizontal, Tokens.padCard)
        .frame(height: 28)
        .overlay(alignment: .top) { Rectangle().fill(Tokens.separator).frame(height: 0.5) }
    }

    private func run() {
        var current = input
        var out: [(String, String)] = []
        for id in steps {
            guard let step = Self.chainable.first(where: { $0.id == id }) else { continue }
            if let result = step.run(current) {
                current = result
                out.append((step.name, result))
            } else {
                out.append((step.name, ""))   // 失败：后续步骤拿不到有效输入
                break
            }
        }
        results = out
    }

    private var finalOutput: String {
        results.last?.output ?? input
    }

    private var outputMeta: String {
        "\(finalOutput.count) 字符"
    }

    private var status: StatusLine {
        if steps.isEmpty {
            return StatusLine(level: .idle, text: "空链条 · 输出等于输入",
                              trailing: "\(Self.chainable.count) 个可用步骤", trailingKey: "⌄")
        }
        if results.count < steps.count || results.contains(where: { $0.output.isEmpty }) {
            let failedAt = results.firstIndex { $0.output.isEmpty }.map { $0 + 1 } ?? results.count
            return StatusLine(level: .error, text: "第 \(failedAt) 步失败，后面的步骤没有执行",
                              trailing: "\(Self.chainable.count) 个可用步骤", trailingKey: "⌄")
        }
        return StatusLine(level: .ok, text: "\(steps.count) 步全部成功",
                          trailing: "\(Self.chainable.count) 个可用步骤", trailingKey: "⌄")
    }
}

// MARK: - 拖放中枢

struct DropHubTool: ToolView {
    static let meta = ToolMeta(
        id: "drophub", name: "拖放中枢", category: .system, layout: .form,
        symbol: "tray.and.arrow.down",
        aliases: ["drop", "hub", "tfzs", "tuofang"]
    )

    @Environment(AppState.self) private var app
    @State private var targeted = false
    @State private var dropped: [URL] = []

    init() {}

    var body: some View {
        StackLayout(status: status) {
            OptionLabel(text: "按类型路由")
            Text("拖进来的文件会自动送到能处理它的工具")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
            Spacer()
            Button("清空") { dropped = [] }.bentoButton().disabled(dropped.isEmpty)
        } content: {
            Card {
                VStack(spacing: 10) {
                    Image(systemName: targeted ? "arrow.down.circle.fill" : "tray.and.arrow.down")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(targeted ? Tokens.accent : Color.secondary)
                    Text("把文件拖到这里").font(Tokens.body)
                    Text("图片 → 压缩/转换 · JSON → 工具箱 · Lottie → 检查 · SVG → SVG 工具 · 其它 → 哈希")
                        .font(Tokens.small).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 34)
                .background(targeted ? Tokens.accent.opacity(0.07) : Color.clear)
                .onDrop(of: [.fileURL], isTargeted: $targeted, perform: handleDrop)
            }
            .fixedSize(horizontal: false, vertical: true)

            Card(title: "路由表", dot: ToolCategory.system.tint, meta: "按扩展名") {
                ResultRows(rows: Self.routes.map { ($0.0.joined(separator: " / "), $0.2) },
                           keyWidth: 176)
            }
            .fixedSize(horizontal: false, vertical: true)

            if !dropped.isEmpty {
                Card(title: "最近拖入", dot: ToolCategory.image.tint, meta: "\(dropped.count) 个") {
                    ResultRows(rows: dropped.map {
                        ($0.pathExtension.uppercased(), $0.lastPathComponent)
                    }, keyWidth: 74)
                        .frame(maxHeight: .infinity)
                }
            }
        }
    }

    /// (扩展名, 目标工具 id, 说明)
    private static let routes: [([String], String, String)] = [
        (["png", "jpg", "jpeg", "heic", "webp", "gif", "tiff", "bmp"], "imgconvert", "图片压缩 / 转换"),
        (["icns", "ico"], "iconset", "图标切图套件"),
        (["json"], "json", "JSON 工具箱（Lottie 会走 Lottie 检查）"),
        (["svg"], "svg", "SVG 工具"),
        (["yaml", "yml"], "yaml", "YAML 互转"),
        (["md", "markdown"], "markdown", "Markdown 预览"),
        (["txt", "log", "csv"], "textdiff", "文本 Diff"),
    ]

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let p = providers.first, p.canLoadObject(ofClass: URL.self) else { return false }
        _ = p.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            DispatchQueue.main.async { route(url) }
        }
        return true
    }

    private func route(_ url: URL) {
        dropped.insert(url, at: 0)
        if dropped.count > 10 { dropped.removeLast() }

        let ext = url.pathExtension.lowercased()
        var target = Self.routes.first { $0.0.contains(ext) }?.1 ?? "hash"

        // .json 要再看一眼内容：Lottie 也是 json
        if ext == "json", let data = try? Data(contentsOf: url),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           obj["layers"] != nil, obj["fr"] != nil {
            target = "lottie"
        }

        // 文本类直接把内容带过去；二进制类只切工具，让工具自己去读文件
        if let text = try? String(contentsOf: url, encoding: .utf8), text.count < 500_000 {
            app.pipe(text, to: target, from: url.lastPathComponent)
        } else {
            app.select(target)
        }
    }

    private var status: StatusLine {
        if let last = dropped.first {
            return StatusLine(level: .ok, text: "已路由 \(last.lastPathComponent)",
                              trailing: "\(Self.routes.count) 条规则", trailingKey: "⌄")
        }
        return StatusLine(level: .idle,
                          text: "等待拖入 · 菜单栏图标接收拖放需要换成 NSStatusItem，留给后续",
                          trailing: "\(Self.routes.count) 条规则", trailingKey: "⌄")
    }
}
