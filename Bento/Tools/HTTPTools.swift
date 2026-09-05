import SwiftUI

// MARK: - HTTP 测试器

struct HTTPTool: ToolView {
    static let meta = ToolMeta(
        id: "http", name: "HTTP 测试器", category: .network, layout: .stacked,
        symbol: "network",
        aliases: ["http", "request", "api", "curl", "qq", "qingqiu"]
    )

    private static let methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]

    @Environment(AppState.self) private var app
    @State private var request = HTTPClient.Request(
        url: "https://httpbin.org/get",
        headers: [HTTPClient.Header(name: "Accept", value: "application/json")]
    )
    @State private var response: HTTPClient.Response?
    @State private var sending = false
    @State private var showRaw = false

    init() {}

    var body: some View {
        StackLayout(status: status) {
            BentoSegments(options: Self.methods.map { ($0, $0) }, selection: $request.method,
                          accent: true)
            TextField("https://…", text: $request.url)
                .textFieldStyle(.plain)
                .font(Tokens.mono)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .sunkenSurface(radius: 7)
                .onSubmit { send() }
            BentoCheck(label: "跟随重定向", isOn: $request.followRedirects)
            Button(sending ? "请求中…" : "发送") { send() }
                .bentoButton(prominent: true)
                .disabled(sending || request.url.trimmed.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
        } content: {
            HStack(alignment: .top, spacing: Tokens.gapCard) {
                Card(title: "请求头", dot: ToolCategory.network.tint,
                     meta: "\(request.headers.filter(\.enabled).count) 条") {
                    headerEditor
                }
                Card(title: "请求体", dot: ToolCategory.encoding.tint,
                     meta: bodyAllowed ? "\(request.body.count) 字符" : "该方法通常不带 body") {
                    CodeArea(text: $request.body,
                             placeholder: bodyAllowed ? "JSON / 表单 / 任意文本…" : "")
                        .disabled(!bodyAllowed)
                }
            }
            .frame(height: 150)

            if let r = response {
                if let error = r.error {
                    Card {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(Tokens.error)
                            Text(error).font(Tokens.body)
                            Spacer()
                        }
                        .padding(Tokens.padCard)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    Card(title: "耗时", dot: ToolCategory.style.tint, meta: timingSummary(r)) {
                        timingBar(r.timing)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .top, spacing: Tokens.gapCard) {
                    Card(title: "响应头", dot: ToolCategory.image.tint,
                         meta: "\(r.headers.count) 条") {
                        ResultRows(rows: r.headers, keyWidth: 168)
                    }
                    Card(title: "响应体", dot: ToolCategory.formatting.tint, meta: bodyMeta(r)) {
                        CodeArea(text: .constant(showRaw ? r.bodyText : r.prettyBody),
                                 isEditable: false)
                        CardFooter {
                            BentoCheck(label: "原始", isOn: $showRaw)
                            Spacer()
                            CopyButton(value: r.prettyBody, compact: false)
                            Button("送到 JSON 工具箱") {
                                app.pipe(r.prettyBody, to: "json", from: "HTTP 响应")
                            }
                            .bentoButton(plain: true)
                            .disabled(!r.isJSON)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 片段

    private var headerEditor: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach($request.headers) { $h in
                        HStack(spacing: 6) {
                            BentoCheck(label: "", isOn: $h.enabled)
                            TextField("Name", text: $h.name)
                                .textFieldStyle(.plain).font(Tokens.mono)
                                .frame(width: 130)
                            TextField("Value", text: $h.value)
                                .textFieldStyle(.plain).font(Tokens.mono)
                                .frame(maxWidth: .infinity)
                            Button {
                                request.headers.removeAll { $0.id == h.id }
                            } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                            .bentoButton(plain: true)
                        }
                        .padding(.horizontal, Tokens.padCard)
                        .frame(height: 26)
                    }
                }
            }
            .scrollIndicators(.never)
            CardFooter {
                Button("加一行") { request.headers.append(HTTPClient.Header(name: "", value: "")) }
                    .bentoButton(plain: true)
                Spacer()
                Button("常用") {
                    request.headers.append(contentsOf: [
                        HTTPClient.Header(name: "Content-Type", value: "application/json"),
                        HTTPClient.Header(name: "User-Agent", value: "Bento/0.1"),
                    ])
                }
                .bentoButton(plain: true)
            }
        }
    }

    /// 分段耗时条 —— 排查「慢」的时候，知道慢在哪一段比知道总时长有用
    private func timingBar(_ t: HTTPClient.Timing) -> some View {
        let segs = t.segments
        let total = max(segs.reduce(0) { $0 + $1.1 }, 0.001)
        let colors: [Color] = [ToolCategory.network.tint, ToolCategory.encoding.tint,
                               ToolCategory.style.tint, ToolCategory.formatting.tint,
                               ToolCategory.image.tint]
        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(Array(segs.enumerated()), id: \.offset) { i, seg in
                        Rectangle()
                            .fill(colors[i % colors.count])
                            .frame(width: max(2, geo.size.width * seg.1 / total))
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 14)
            .clipShape(.rect(cornerRadius: 4))

            HStack(spacing: 14) {
                ForEach(Array(segs.enumerated()), id: \.offset) { i, seg in
                    HStack(spacing: 4) {
                        Circle().fill(colors[i % colors.count]).frame(width: 6, height: 6)
                        Text("\(seg.0) \(Int(seg.1))ms")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if t.reusedConnection {
                    Text("复用连接").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                if let p = t.protocolName {
                    Text(p.uppercased()).font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, Tokens.padCard)
        .padding(.bottom, Tokens.padCard)
    }

    // MARK: -

    private var bodyAllowed: Bool { !["GET", "HEAD"].contains(request.method) }

    private func bodyMeta(_ r: HTTPClient.Response) -> String {
        "\(ImageKit.byteString(r.body.count))" + (r.isJSON ? " · JSON" : "")
    }

    private func timingSummary(_ r: HTTPClient.Response) -> String {
        String(format: "总 %.0f ms", r.timing.total)
            + (r.redirectCount > 0 ? " · \(r.redirectCount) 次重定向" : "")
    }

    private func send() {
        guard !sending else { return }
        sending = true
        let req = request
        Task {
            let result = await HTTPClient.send(req)
            await MainActor.run {
                response = result
                sending = false
            }
        }
    }

    private var status: StatusLine {
        if sending {
            return StatusLine(level: .warning, text: "请求中…", trailing: "URLSession", trailingKey: "⌄")
        }
        guard let r = response else {
            return StatusLine(level: .idle, text: "⌘↩ 发送 · 分段耗时来自 URLSessionTaskMetrics",
                              trailing: "URLSession", trailingKey: "⌄")
        }
        if let e = r.error {
            return StatusLine(level: .error, text: e, trailing: "URLSession", trailingKey: "⌄")
        }
        let level: StatusLine.Level = r.statusColorLevel == 0 ? .ok
            : (r.statusColorLevel == 1 ? .warning : .error)
        return StatusLine(level: level,
                          text: "\(r.status) \(r.statusText) · \(ImageKit.byteString(r.body.count))"
                              + String(format: " · %.0f ms", r.timing.total),
                          trailing: r.timing.protocolName?.uppercased() ?? "HTTP", trailingKey: "⌄")
    }
}

// MARK: - 响应头分析

struct HeaderTool: ToolView {
    static let meta = ToolMeta(
        id: "headers", name: "响应头分析", category: .network, layout: .stacked,
        symbol: "list.bullet.rectangle",
        aliases: ["headers", "security", "csp", "hsts", "xytf", "xiangying"]
    )

    @State private var url = "https://example.com"
    @State private var raw = ""
    @State private var fetching = false
    @State private var fetchError: String?

    init() {}

    var body: some View {
        StackLayout(status: status) {
            TextField("https://…", text: $url)
                .textFieldStyle(.plain)
                .font(Tokens.mono)
                .padding(.horizontal, 10)
                .frame(width: 300, height: 28)
                .sunkenSurface(radius: 7)
                .onSubmit { fetch() }
            Button(fetching ? "抓取中…" : "抓取") { fetch() }
                .bentoButton(prominent: true)
                .disabled(fetching)
            Spacer()
            Text("也可以直接粘贴 curl -I 的输出")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
        } content: {
            HStack(alignment: .top, spacing: Tokens.gapCard) {
                Card(title: "原始响应头", dot: ToolCategory.network.tint,
                     meta: "\(headers.count) 条") {
                    CodeArea(text: $raw, placeholder: "抓取，或粘贴 curl -I 的输出…")
                }
                .frame(width: 340)

                VStack(spacing: Tokens.gapCard) {
                    Card(title: "安全", dot: scoreColor, meta: "\(report.score) / 100") {
                        findings(report.security)
                    }
                    Card(title: "缓存", dot: ToolCategory.style.tint,
                         meta: "\(report.caching.count) 项") {
                        findings(report.caching)
                    }
                    Card(title: "常规", dot: ToolCategory.image.tint,
                         meta: "\(report.general.count) 项") {
                        findings(report.general)
                    }
                }
            }
        }
    }

    private func findings(_ list: [HeaderAnalyzer.Finding]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.offset) { _, f in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: icon(f.level))
                            .font(.system(size: 10))
                            .foregroundStyle(color(f.level))
                            .frame(width: 14)
                        Text(f.title)
                            .font(.system(size: 11.5, weight: .medium))
                            .frame(width: 150, alignment: .leading)
                        Text(f.detail)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, Tokens.padCard)
                    .padding(.vertical, 5)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Tokens.separator).frame(height: 0.5)
                    }
                }
            }
        }
        .scrollIndicators(.never)
    }

    private func icon(_ l: HeaderAnalyzer.Level) -> String {
        switch l {
        case .good: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .bad:  return "xmark.circle.fill"
        case .info: return "info.circle"
        }
    }

    private func color(_ l: HeaderAnalyzer.Level) -> Color {
        switch l {
        case .good: return Tokens.ok
        case .warn: return Tokens.warning
        case .bad:  return Tokens.error
        case .info: return Tokens.tertiaryLabel
        }
    }

    private var headers: [(String, String)] { HeaderAnalyzer.parse(raw) }
    private var report: HeaderAnalyzer.Report { HeaderAnalyzer.analyze(headers) }

    private var scoreColor: Color {
        report.score >= 80 ? Tokens.ok : (report.score >= 50 ? Tokens.warning : Tokens.error)
    }

    private func fetch() {
        guard !fetching else { return }
        fetching = true
        fetchError = nil
        var req = HTTPClient.Request(method: "HEAD", url: url)
        req.followRedirects = true
        Task {
            var r = await HTTPClient.send(req)
            // 有些站点对 HEAD 返回 405，退回 GET 再拿一次头
            if r.error != nil || r.status == 405 {
                req.method = "GET"
                r = await HTTPClient.send(req)
            }
            await MainActor.run {
                if let e = r.error {
                    fetchError = e
                } else {
                    raw = "HTTP \(r.status)\n"
                        + r.headers.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
                }
                fetching = false
            }
        }
    }

    private var status: StatusLine {
        if fetching {
            return StatusLine(level: .warning, text: "抓取中…", trailing: "HEAD", trailingKey: "⌄")
        }
        if let e = fetchError {
            return StatusLine(level: .error, text: e, trailing: "HEAD", trailingKey: "⌄")
        }
        if headers.isEmpty {
            return StatusLine(level: .idle, text: "抓取一个 URL，或粘贴响应头",
                              trailing: "OWASP", trailingKey: "⌄")
        }
        let bad = report.security.filter { $0.level == .bad || $0.level == .warn }.count
        return StatusLine(level: bad == 0 ? .ok : .warning,
                          text: "安全评分 \(report.score)/100 · \(bad) 项待改进",
                          trailing: "OWASP", trailingKey: "⌄")
    }
}
