import SwiftUI

// MARK: - 剪贴板监听

struct ClipboardMonitorTool: ToolView {
    static let meta = ToolMeta(
        id: "clipmonitor", name: "剪贴板监听", category: .system, layout: .form,
        symbol: "doc.on.clipboard",
        aliases: ["clipboard", "monitor", "jtb", "jianting"]
    )

    @Environment(AppState.self) private var app

    init() {}

    var body: some View {
        @Bindable var monitor = app.clipboard

        StackLayout(status: status) {
            Button(app.clipboard.isRunning ? "停止监听" : "开始监听") {
                app.clipboard.toggle()
            }
            .bentoButton(prominent: !app.clipboard.isRunning)
            OptionLabel(text: "轮询间隔")
            Slider(value: $monitor.interval, in: 0.2...2, step: 0.1)
                .frame(width: 120)
                .onChange(of: app.clipboard.interval) { _, _ in
                    app.clipboard.restartTimerIfNeeded()
                }
            Text(String(format: "%.1f s", app.clipboard.interval))
                .font(Tokens.mono).monospacedDigit().frame(width: 44)
            BentoCheck(label: "跳过密码类内容", isOn: $monitor.skipConcealed)
            Spacer()
        } content: {
            Card(title: "当前剪贴板", dot: ToolCategory.system.tint, meta: currentMeta) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(app.clipboard.currentText.isEmpty ? "（空）"
                         : String(app.clipboard.currentText.prefix(600)))
                        .font(Tokens.mono)
                        .lineLimit(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .sunkenSurface(radius: 8)

                    if let hit = app.clipboard.detected {
                        HStack(spacing: 12) {
                            Image(systemName: hit.symbol)
                                .foregroundStyle(Tokens.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(hit.kindLabel) · \(hit.value)")
                                    .font(.system(size: 13, design: .monospaced))
                                    .lineLimit(1)
                                Text(hit.detail).font(Tokens.small).foregroundStyle(.secondary)
                            }
                            Spacer()
                            ForEach(hit.relatedToolNames.prefix(2), id: \.self) { name in
                                if let item = resolve(name) {
                                    Button(item.name) { app.pipe(app.clipboard.currentText,
                                                                 to: item.id, from: "剪贴板") }
                                        .bentoButton(prominent: name == hit.relatedToolNames.first)
                                }
                            }
                            CopyButton(value: hit.value)
                        }
                    } else {
                        Text("没有识别到可直接处理的内容")
                            .font(Tokens.small).foregroundStyle(.tertiary)
                    }
                }
                .padding(Tokens.padCard)
            }
            .fixedSize(horizontal: false, vertical: true)

            Card(title: "工作原理", dot: ToolCategory.formatting.tint, meta: "NSPasteboard") {
                ResultRows(rows: infoRows, keyWidth: 132)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private func resolve(_ name: String) -> ToolItem? {
        ToolRegistry.items.first { $0.name == name && $0.implemented }
    }

    private var currentMeta: String {
        guard let d = app.clipboard.lastChange else { return "—" }
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        return "更新于 \(f.string(from: d))"
    }

    private var infoRows: [(String, String)] {
        [
            ("机制", "NSPasteboard 没有变更通知，只能轮询 changeCount（单调递增的整数）"),
            ("开销", "每 \(String(format: "%.1f", app.clipboard.interval))s 比一次整数；"
                + "只有 changeCount 变了才真正读内容"),
            ("已轮询", "\(app.clipboard.pollCount) 次"),
            ("隐私", app.clipboard.skipConcealed
                ? "跳过带 org.nspasteboard.ConcealedType 标记的内容（密码管理器会打这个标记）"
                : "⚠︎ 未跳过密码类内容"),
            ("历史上限", "\(app.clipboard.maxHistory) 条（置顶项不计入）· 单条超过 \(app.clipboard.maxLength) 字符不记录"),
            ("菜单栏", "识别到可处理内容时，菜单栏图标会变成实心"),
        ]
    }

    private var status: StatusLine {
        guard app.clipboard.isRunning else {
            return StatusLine(level: .idle, text: "监听已停止", trailing: "⌘⇧M 开关", trailingKey: "⌄")
        }
        if let hit = app.clipboard.detected {
            return StatusLine(level: .ok,
                              text: "监听中 · 当前是 \(hit.kindLabel)：\(hit.value.prefix(40))",
                              trailing: "⌘⇧M 开关", trailingKey: "⌄")
        }
        return StatusLine(level: .ok,
                          text: "监听中 · 已记录 \(app.clipboard.history.count) 条",
                          trailing: "⌘⇧M 开关", trailingKey: "⌄")
    }
}

// MARK: - 剪贴板历史

struct ClipboardHistoryTool: ToolView {
    static let meta = ToolMeta(
        id: "cliphistory", name: "剪贴板历史", category: .system, layout: .stacked,
        symbol: "clock.arrow.circlepath",
        aliases: ["history", "clipboard", "jtbls", "lishi"]
    )

    @Environment(AppState.self) private var app
    @State private var query = ""

    init() {}

    var body: some View {
        StackLayout(status: status) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                TextField("搜索历史", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 12))
            }
            .padding(.horizontal, 8)
            .frame(width: 200, height: 26)
            .sunkenSurface(radius: 7)
            Spacer()
            Text("\(app.clipboard.pinnedCount) 条置顶")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
            Button("清空未置顶") { app.clipboard.clearUnpinned() }
                .bentoButton()
                .disabled(app.clipboard.history.allSatisfy(\.pinned))
        } content: {
            Card(title: "历史", dot: ToolCategory.system.tint,
                 meta: "\(filtered.count) / \(app.clipboard.history.count)") {
                if filtered.isEmpty {
                    Text(app.clipboard.isRunning
                         ? "还没有记录 —— 复制点什么试试"
                         : "监听未开启 · 到「剪贴板监听」里打开")
                        .font(Tokens.body).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filtered) { entry in
                                row(entry)
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
            }
        }
    }

    private func row(_ entry: ClipboardMonitor.Entry) -> some View {
        HStack(spacing: 10) {
            Button {
                app.clipboard.togglePin(entry)
            } label: {
                Image(systemName: entry.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 10))
                    .foregroundStyle(entry.pinned
                                     ? AnyShapeStyle(Color(nsColor: .systemYellow))
                                     : AnyShapeStyle(.tertiary))
            }
            .buttonStyle(.plain)
            .frame(width: 18)

            if let kind = entry.kindLabel {
                Text(kind)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Tokens.accent)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Tokens.accent.opacity(0.15), in: .rect(cornerRadius: 4))
                    .frame(width: 54)
            } else {
                Color.clear.frame(width: 54, height: 1)
            }

            Text(entry.preview)
                .font(Tokens.mono)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(time(entry.date))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)

            Button("回填") { app.clipboard.copyBack(entry) }
                .bentoButton(plain: true)
            Button {
                app.clipboard.remove(entry)
            } label: {
                Image(systemName: "xmark").font(.system(size: 9))
            }
            .bentoButton(plain: true)
        }
        .padding(.horizontal, Tokens.padCard)
        .frame(height: 30)
        .overlay(alignment: .top) { Rectangle().fill(Tokens.separator).frame(height: 0.5) }
    }

    private var filtered: [ClipboardMonitor.Entry] {
        guard !query.trimmed.isEmpty else { return app.clipboard.history }
        return app.clipboard.history.filter {
            $0.text.localizedCaseInsensitiveContains(query.trimmed)
        }
    }

    private func time(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }

    private var status: StatusLine {
        app.clipboard.isRunning
            ? StatusLine(level: .ok,
                         text: "\(app.clipboard.history.count) 条 · 置顶项不会被自动清理 · 仅存在内存中，退出即清空",
                         trailing: "内存", trailingKey: "⌄")
            : StatusLine(level: .warning, text: "监听未开启，不会记录新内容",
                         trailing: "内存", trailingKey: "⌄")
    }
}
