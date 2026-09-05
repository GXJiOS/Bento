import SwiftUI
import AppKit

@main
struct BentoMain {
    static func main() {
        // CLI 模式：直接处理并退出，不启动 UI。
        // 必须在 App.main() 之前拦截，否则 SwiftUI 会先把窗口建起来。
        if CLIRunner.runIfNeeded() { return }
        BentoApp.main()
    }
}

struct BentoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let app = AppState.shared

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environment(app)
        }
        .defaultSize(width: 1020, height: 660)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands { commands }

        MenuBarExtra {
            MenuBarPanel()
                .environment(app)
        } label: {
            // 剪贴板里有可处理内容时换成实心图标 —— 菜单栏会把图标按 template 渲染，
            // 用形状区分比用颜色可靠
            Image(systemName: app.clipboard.detected != nil
                  ? "square.grid.2x2.fill" : "square.grid.2x2")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(app)
        }
    }

    @CommandsBuilder
    private var commands: some Commands {
        CommandGroup(after: .newItem) {
            Button("命令面板") { app.paletteOpen = true }
                .keyboardShortcut("k", modifiers: .command)
            Button(app.clipboard.isRunning ? "停止剪贴板监听" : "开始剪贴板监听") {
                app.clipboard.toggle()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .toolbar) {
            ForEach(Array(app.favorites.prefix(9).enumerated()), id: \.offset) { index, id in
                if let item = ToolRegistry.item(id: id) {
                    Button(item.name) { app.select(id) }
                        .keyboardShortcut(
                            KeyEquivalent(Character("\(index + 1)")), modifiers: .command
                        )
                }
            }
        }
    }
}

/// 热键、Services、剪贴板这些系统级能力活在 SwiftUI 视图树之外，统一在这里装配
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: GlobalHotKey?
    private(set) var paletteController: PalettePanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let state = AppState.shared

        let controller = PalettePanelController(app: state)
        paletteController = controller
        registerHotKey(state, controller)

        if state.clipboardAutoStart { state.clipboard.start() }

        NSApp.servicesProvider = ServicesProvider()
        NSUpdateDynamicServices()
    }

    /// 换热键时重新注册
    func registerHotKey(_ state: AppState, _ controller: PalettePanelController) {
        hotKey = GlobalHotKey(state.hotKeyCombo) { [weak controller] in
            controller?.toggle()
        }
        state.hotKeyRegistered = hotKey != nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false   // 关掉主窗口仍留在菜单栏
    }

    /// 退出前把防抖里还没落盘的东西写完
    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.saveNow()
    }
}
