import SwiftUI
import AppKit

// MARK: - 全局热键

struct HotKeyTool: ToolView {
    static let meta = ToolMeta(
        id: "hotkey", name: "全局热键", category: .system, layout: .form,
        symbol: "command.square",
        aliases: ["hotkey", "shortcut", "qjrj", "rejian"]
    )

    @Environment(AppState.self) private var app

    private static let choices: [(String, GlobalHotKey.Combo)] = [
        ("⌥Space", .optionSpace),
        ("⌃Space", .controlSpace),
        ("⌘⇧B", .commandShiftB),
    ]

    init() {}

    var body: some View {
        StackLayout(status: status) {
            OptionLabel(text: "唤起命令面板")
            ForEach(Self.choices, id: \.0) { name, combo in
                Button(name) { apply(combo) }
                    .bentoButton(prominent: app.hotKeyCombo == combo)
            }
            Spacer()
            Text("改完立即生效").font(.system(size: 12)).foregroundStyle(.tertiary)
        } content: {
            Card(title: "当前热键", dot: ToolCategory.system.tint,
                 meta: app.hotKeyRegistered ? "已注册" : "注册失败") {
                HStack(spacing: 16) {
                    Text(app.hotKeyCombo.display)
                        .font(.system(size: 34, weight: .medium, design: .rounded))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.hotKeyRegistered ? "在任何 App 里按都能唤起面板"
                                                  : "注册失败 —— 这个组合多半被别的 App 占了")
                            .font(Tokens.body)
                            .foregroundStyle(app.hotKeyRegistered
                                             ? AnyShapeStyle(.secondary)
                                             : AnyShapeStyle(Tokens.error))
                        Text("面板会浮在最前，失焦自动隐藏；Esc 关闭")
                            .font(Tokens.small).foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(Tokens.padCard)
            }
            .fixedSize(horizontal: false, vertical: true)

            Card(title: "实现说明", dot: ToolCategory.formatting.tint, meta: "Carbon") {
                ResultRows(rows: [
                    ("API", "RegisterEventHotKey（Carbon）—— 系统级注册，App 在后台也能收到"),
                    ("权限", "不需要辅助功能权限。NSEvent.addGlobalMonitor 那条路才需要"),
                    ("面板", "NSPanel + .nonactivatingPanel，唤起时不抢当前 App 的激活状态"),
                    ("多屏", "出现在鼠标所在那块屏幕的上方 22% 处"),
                    ("全屏", ".canJoinAllSpaces + .fullScreenAuxiliary，别的 App 全屏时也能浮出来"),
                ], keyWidth: 74)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private func apply(_ combo: GlobalHotKey.Combo) {
        app.hotKeyCombo = combo
        guard let delegate = NSApp.delegate as? AppDelegate,
              let controller = delegate.paletteController else { return }
        delegate.registerHotKey(app, controller)
    }

    private var status: StatusLine {
        app.hotKeyRegistered
            ? StatusLine(level: .ok, text: "\(app.hotKeyCombo.display) 已生效 · 试试切到别的 App 再按",
                         trailing: "Carbon", trailingKey: "⌄")
            : StatusLine(level: .error, text: "注册失败 · 换一个组合试试",
                         trailing: "Carbon", trailingKey: "⌄")
    }
}

// MARK: - Services 菜单

struct ServicesTool: ToolView {
    static let meta = ToolMeta(
        id: "services", name: "Services 菜单", category: .system, layout: .form,
        symbol: "contextualmenu.and.cursorarrow",
        aliases: ["services", "menu", "fwcd", "fuwu"]
    )

    init() {}

    var body: some View {
        StackLayout(status: status) {
            OptionLabel(text: "系统服务")
            Text("在任何 App 里选中文本 → 右键「服务」")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
            Spacer()
            Button("刷新服务注册") { NSUpdateDynamicServices() }.bentoButton()
            Button("打开系统设置…") {
                NSWorkspace.shared.open(URL(string:
                    "x-apple.systempreferences:com.apple.ExtensionsPreferences?Services")!)
            }
            .bentoButton(prominent: true)
        } content: {
            Card(title: "已注册的服务", dot: ToolCategory.system.tint, meta: "5 项") {
                ResultRows(rows: [
                    ("Bento：识别并处理", "自动判断类型后跳到对应工具，并把文本带过去"),
                    ("Bento：格式化 JSON", "原地替换选中文本"),
                    ("Bento：Base64 编码", "原地替换"),
                    ("Bento：Base64 解码", "原地替换"),
                    ("Bento：URL 解码", "原地替换"),
                ], keyWidth: 168)
            }
            .fixedSize(horizontal: false, vertical: true)

            Card(title: "怎么用", dot: ToolCategory.formatting.tint, meta: "说明") {
                ResultRows(rows: [
                    ("原地替换", "在可编辑的地方（备忘录、Xcode、输入框）选中文本调用，结果直接替换原文"),
                    ("只读的地方", "在网页这类不可编辑处调用，结果会写回剪贴板"),
                    ("看不到菜单？", "首次安装后点上面「刷新服务注册」，或到系统设置 → 键盘 → 键盘快捷键 → 服务里勾上"),
                    ("加快捷键", "在同一个设置页可以给每项服务绑快捷键"),
                    ("实现", "Info.plist 的 NSServices + NSApp.servicesProvider"),
                ], keyWidth: 96)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private var status: StatusLine {
        StatusLine(level: .ok,
                   text: "5 项服务已随 App 注册 · 首次可能要点一次「刷新服务注册」才出现",
                   trailing: "NSServices", trailingKey: "⌄")
    }
}

// MARK: - 快捷指令

struct ShortcutsTool: ToolView {
    static let meta = ToolMeta(
        id: "shortcuts", name: "快捷指令动作", category: .system, layout: .form,
        symbol: "app.connected.to.app.below.fill",
        aliases: ["shortcuts", "intents", "kjzl", "kuaijie"]
    )

    init() {}

    var body: some View {
        StackLayout(status: status) {
            OptionLabel(text: "App Intents")
            Text("可在快捷指令 App、Spotlight 和 shortcuts 命令里调用")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
            Spacer()
            Button("打开快捷指令…") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
            }
            .bentoButton(prominent: true)
        } content: {
            Card(title: "已暴露的动作", dot: ToolCategory.system.tint, meta: "6 个") {
                ResultRows(rows: [
                    ("Base64 编码", "参数：文本、URL-safe → 返回字符串"),
                    ("Base64 解码", "参数：Base64 → 返回字符串"),
                    ("格式化 JSON", "参数：JSON、排序键 → 返回字符串"),
                    ("计算哈希", "参数：文本、算法（MD5/SHA-1/SHA-256/SHA-512）"),
                    ("生成 UUID", "参数：数量、是否用 v7 → 返回字符串数组"),
                    ("识别内容类型", "参数：文本 → 返回类型与解读"),
                ], keyWidth: 118)
            }
            .fixedSize(horizontal: false, vertical: true)

            Card(title: "命令行调用", dot: ToolCategory.formatting.tint, meta: "shortcuts(1)") {
                CodeArea(text: .constant("""
                # 列出本机所有快捷指令
                shortcuts list

                # 建好快捷指令后可以直接跑，也能接管道
                echo '{"a":1}' | shortcuts run "格式化 JSON"

                # 也可以用 Bento 自带的 CLI（更直接，见「CLI 伴生」）
                echo '{"a":1}' | bento json
                """), isEditable: false)
            }
        }
    }

    private var status: StatusLine {
        StatusLine(level: .ok,
                   text: "6 个动作已注册 · 其中 3 个会出现在快捷指令的建议列表里",
                   trailing: "AppIntents", trailingKey: "⌄")
    }
}

// MARK: - CLI 伴生

struct CLITool: ToolView {
    static let meta = ToolMeta(
        id: "cli", name: "CLI 伴生", category: .system, layout: .form,
        symbol: "terminal",
        aliases: ["cli", "terminal", "command", "mlh", "minglinghang"]
    )

    @State private var installed = CLIRunner.isInstalled
    @State private var message: String?
    @State private var failed = false

    init() {}

    var body: some View {
        StackLayout(status: status) {
            OptionLabel(text: "/usr/local/bin/bento")
            Spacer()
            if installed {
                Button("卸载") { CLIRunner.uninstall(); refresh() }.bentoButton()
            } else {
                Button("安装") { install() }.bentoButton(prominent: true)
            }
            Button("重新检测") { refresh() }.bentoButton(plain: true)
        } content: {
            Card(title: "状态", dot: ToolCategory.system.tint,
                 meta: installed ? "已安装" : "未安装") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(installed ? Tokens.ok : Tokens.tertiaryLabel)
                            .frame(width: 8, height: 8)
                        Text(installed
                             ? "已装到 /usr/local/bin/bento，终端里直接敲 bento 就能用"
                             : "还没装 —— 点右上角「安装」")
                            .font(Tokens.body)
                        Spacer()
                    }
                    if let message {
                        Text(message)
                            .font(Tokens.small)
                            .foregroundStyle(failed ? Tokens.error : Tokens.ok)
                            .textSelection(.enabled)
                            .padding(9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .sunkenSurface(radius: 7)
                    }
                    Text("原理：App 的主二进制同时也是 CLI —— 启动 SwiftUI 之前先看有没有命令行参数，"
                         + "有就处理完直接退出，界面一次都不会建。装的只是一个 exec 到它的 wrapper。")
                        .font(Tokens.small).foregroundStyle(.tertiary)
                }
                .padding(Tokens.padCard)
            }
            .fixedSize(horizontal: false, vertical: true)

            Card(title: "命令", dot: ToolCategory.formatting.tint,
                 meta: "\(CLIRunner.commands.count) 个") {
                ResultRows(rows: CLIRunner.commands.map { ($0.usage, $0.help) }, keyWidth: 176)
            }
            .fixedSize(horizontal: false, vertical: true)

            Card(title: "例子", dot: ToolCategory.image.tint, meta: "支持管道") {
                CodeArea(text: .constant("""
                bento b64 "Hello, 世界"          # SGVsbG8sIOS4lueVjA==
                bento b64 -d SGVsbG8=            # Hello
                bento hash md5 Hello             # 8b1a9953c46112...
                bento uuid 5 -7                  # 5 个时间有序 UUID
                bento ts 1735689600              # 2025-01-01 08:00:00 +0800
                bento case snake HTTPServerConfig  # http_server_config

                echo '{"b":2,"a":1}' | bento json     # 格式化
                pbpaste | bento detect               # 识别剪贴板内容
                cat api.json | bento json -c | pbcopy # 压缩后回写剪贴板
                """), isEditable: false)
            }
        }
    }

    private func install() {
        switch CLIRunner.install() {
        case .success(let path):
            failed = false
            message = "已写入 \(path)"
        case .failure(let error):
            failed = true
            message = error.localizedDescription
        }
        refresh()
    }

    private func refresh() {
        installed = CLIRunner.isInstalled
    }

    private var status: StatusLine {
        installed
            ? StatusLine(level: .ok, text: "bento 已在 PATH 上 · 试试 bento --help",
                         trailing: "非沙盒", trailingKey: "⌄")
            : StatusLine(level: .idle, text: "未安装 · 装了之后终端和脚本里都能用",
                         trailing: "非沙盒", trailingKey: "⌄")
    }
}
