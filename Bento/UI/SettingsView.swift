import SwiftUI
import UniformTypeIdentifiers

/// ⌘, 打开。SwiftUI 的 Settings scene 自带 macOS 设置窗口的外观和 tab 栏。
struct SettingsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("通用", systemImage: "gearshape") }
            ClipboardSettings().tabItem { Label("剪贴板", systemImage: "doc.on.clipboard") }
            ToolsSettings().tabItem { Label("工具", systemImage: "square.grid.2x2") }
            DataSettings().tabItem { Label("数据", systemImage: "internaldrive") }
            AboutSettings().tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 430)
    }
}

// MARK: - 通用

private struct GeneralSettings: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        Form {
            Section("命令面板") {
                Picker("全局热键", selection: $app.settings.hotKeyCombo) {
                    Text("⌥Space").tag(GlobalHotKey.Combo.optionSpace)
                    Text("⌃Space").tag(GlobalHotKey.Combo.controlSpace)
                    Text("⌘⇧B").tag(GlobalHotKey.Combo.commandShiftB)
                }
                .onChange(of: app.settings.hotKeyCombo) { _, _ in reregister() }

                LabeledContent("状态") {
                    Label(app.hotKeyRegistered ? "已注册" : "注册失败（组合可能被占用）",
                          systemImage: app.hotKeyRegistered ? "checkmark.circle" : "xmark.circle")
                        .foregroundStyle(app.hotKeyRegistered ? Tokens.ok : Tokens.error)
                        .font(.caption)
                }
                Text("窗口内还可以用 ⌘K 打开面板")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("工具") {
                Toggle("记住每个工具上次的输入", isOn: $app.settings.rememberToolInputs)
                Text("只保留当前输入，不留历史；超过 32KB 的内容不记。存在 "
                     + "~/Library/Application Support/Bento/")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func reregister() {
        guard let delegate = NSApp.delegate as? AppDelegate,
              let controller = delegate.paletteController else { return }
        delegate.registerHotKey(app, controller)
    }
}

// MARK: - 剪贴板

private struct ClipboardSettings: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        Form {
            Section("监听") {
                Toggle("启动时自动开始", isOn: $app.settings.clipboardAutoStart)
                LabeledContent("当前状态") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(app.clipboard.isRunning ? Tokens.ok : Tokens.tertiaryLabel)
                            .frame(width: 7, height: 7)
                        Text(app.clipboard.isRunning
                             ? "监听中 · 已轮询 \(app.clipboard.pollCount) 次" : "已停止")
                            .font(.caption)
                        Button(app.clipboard.isRunning ? "停止" : "开始") {
                            app.clipboard.toggle()
                        }
                        .controlSize(.small)
                    }
                }
                Slider(value: $app.settings.clipboardInterval, in: 0.2...2, step: 0.1) {
                    Text("轮询间隔")
                } minimumValueLabel: {
                    Text("0.2s").font(.caption)
                } maximumValueLabel: {
                    Text("2s").font(.caption)
                }
                Text(String(format: "当前 %.1f 秒 —— 只比较一个整数，间隔小一点也不费电",
                            app.settings.clipboardInterval))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("隐私") {
                Toggle("跳过密码类内容", isOn: $app.settings.clipboardSkipConcealed)
                Text("密码管理器会给内容打 org.nspasteboard.ConcealedType 标记，"
                     + "勾上就不读也不记")
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("把历史保存到磁盘", isOn: $app.settings.clipboardPersistHistory)
                Label(app.settings.clipboardPersistHistory
                      ? "会写入 clipboard.json（置顶项 + 最近 20 条）"
                      : "默认不写盘 —— 退出即清空",
                      systemImage: app.settings.clipboardPersistHistory
                      ? "exclamationmark.triangle" : "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(app.settings.clipboardPersistHistory
                                     ? Tokens.warning : Tokens.ok)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 工具管理

private struct ToolsSettings: View {
    @Environment(AppState.self) private var app
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("搜索", text: $query).textFieldStyle(.roundedBorder)
                Text("\(app.hidden.count) 个已隐藏")
                    .font(.caption).foregroundStyle(.secondary)
                Button("全部显示") { app.hidden.removeAll(); app.scheduleSave() }
                    .controlSize(.small)
                    .disabled(app.hidden.isEmpty)
            }
            .padding(12)

            List {
                Section("收藏（拖动排序，⌘1…⌘9 依次对应）") {
                    ForEach(app.favoriteItems) { item in
                        HStack {
                            CategoryIcon(symbol: item.symbol, tint: item.category.tint, size: 18)
                            Text(item.name)
                            Spacer()
                            Button {
                                app.toggleFavorite(item.id)
                            } label: { Image(systemName: "star.slash") }
                            .buttonStyle(.borderless)
                        }
                    }
                    .onMove { app.moveFavorite(from: $0, to: $1) }
                }

                ForEach(ToolCategory.allCases) { category in
                    let items = ToolRegistry.items(in: category)
                        .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
                    if !items.isEmpty {
                        Section(category.title) {
                            ForEach(items) { item in
                                HStack {
                                    CategoryIcon(symbol: item.symbol,
                                                 tint: item.category.tint, size: 18)
                                    Text(item.name)
                                        .foregroundStyle(app.hidden.contains(item.id)
                                                         ? AnyShapeStyle(.tertiary)
                                                         : AnyShapeStyle(.primary))
                                    Spacer()
                                    Button {
                                        app.toggleFavorite(item.id)
                                    } label: {
                                        Image(systemName: app.isFavorite(item.id)
                                              ? "star.fill" : "star")
                                    }
                                    .buttonStyle(.borderless)
                                    Toggle("", isOn: Binding(
                                        get: { !app.hidden.contains(item.id) },
                                        set: { _ in app.toggleHidden(item.id) }
                                    ))
                                    .toggleStyle(.switch)
                                    .controlSize(.mini)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 数据

private struct DataSettings: View {
    @Environment(AppState.self) private var app
    @State private var message: String?

    var body: some View {
        Form {
            Section("存储位置") {
                LabeledContent("目录") {
                    Button(Persistence.directory.path) {
                        NSWorkspace.shared.open(Persistence.directory)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
                ForEach(Persistence.File.allCases, id: \.rawValue) { file in
                    LabeledContent(file.label) {
                        Text(file.exists ? ImageKit.byteString(file.byteCount) : "未创建")
                            .font(.caption)
                            .foregroundStyle(file.exists ? .secondary : .tertiary)
                    }
                }
                LabeledContent("合计") {
                    Text(ImageKit.byteString(Persistence.totalBytes)).font(.caption)
                }
            }

            Section("工具输入记忆") {
                LabeledContent("已记住") {
                    Text("\(ToolMemory.shared.count) 个工具 · "
                         + "\(ToolMemory.shared.totalCharacters) 字符")
                        .font(.caption)
                }
                Button("清空输入记忆") { ToolMemory.shared.clear() }
            }

            Section("备份") {
                HStack {
                    Button("导出配置…") { export() }
                    Button("导入配置…") { importConfig() }
                    Spacer()
                    Button("恢复默认设置") { app.resetAll(); message = "已恢复默认" }
                        .foregroundStyle(Tokens.error)
                }
                if let message {
                    Text(message).font(.caption).foregroundStyle(Tokens.ok)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func export() {
        app.saveNow()
        guard let data = Persistence.exportBundle() else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "bento-config.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
            message = "已导出到 \(url.lastPathComponent)"
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        let n = Persistence.importBundle(data)
        message = n > 0 ? "已导入 \(n) 个文件 —— 重启 App 后生效" : "文件格式不对"
    }
}

// MARK: - 关于

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Tokens.accent)
            Text("Bento").font(.system(size: 22, weight: .semibold))
            Text("本地自用的 macOS 工具集")
                .font(.caption).foregroundStyle(.secondary)

            Divider().padding(.horizontal, 60)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("版本").foregroundStyle(.secondary)
                    Text(version)
                }
                GridRow {
                    Text("工具").foregroundStyle(.secondary)
                    Text("\(ToolRegistry.implementedCount) 个")
                }
                GridRow {
                    Text("沙盒").foregroundStyle(.secondary)
                    Text("未启用 —— 所以能调 iconutil / dig / openssl，能读任意路径")
                }
                GridRow {
                    Text("更新").foregroundStyle(.secondary)
                    Text("无自动更新 —— 自己用，重新 build 就行")
                }
            }
            .font(.caption)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
