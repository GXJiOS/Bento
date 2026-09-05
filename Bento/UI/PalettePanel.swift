import SwiftUI
import AppKit

/// 承载命令面板的独立浮窗。
///
/// 关键几点：
/// - `.nonactivatingPanel`：唤起时不抢当前 App 的激活状态，关掉后焦点自然回去
/// - `canBecomeKey` 必须重写，否则 borderless panel 收不到键盘输入
/// - `.canJoinAllSpaces` + `.fullScreenAuxiliary`：别的 App 全屏时也能浮出来
final class PalettePanelController: NSObject, NSWindowDelegate {

    private var panel: KeyablePanel?
    private let app: AppState

    init(app: AppState) {
        self.app = app
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel

        app.paletteQuery = ""
        // 放在当前鼠标所在屏幕的上方 22% 处 —— 多屏时跟着眼睛走
        if let screen = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) ?? NSScreen.main {
            let size = panel.frame.size
            let x = screen.frame.midX - size.width / 2
            let y = screen.frame.maxY - screen.frame.height * 0.22 - size.height
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
        app.paletteQuery = ""
    }

    private func makePanel() -> KeyablePanel {
        let content = PaletteContent(onDismiss: { [weak self] in self?.hide() })
            .environment(app)
            .frame(width: Tokens.paletteW)
            .fixedSize(horizontal: true, vertical: true)

        let hosting = NSHostingView(rootView: content)
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: Tokens.paletteW, height: 200),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.hide() }
        panel.setContentSize(hosting.fittingSize)
        return panel
    }

    /// 失焦即隐藏 —— 面板类工具的通用行为
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}

final class KeyablePanel: NSPanel {
    var onEscape: (() -> Void)?

    // borderless panel 默认不能成为 key window，不重写就收不到键盘
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}
