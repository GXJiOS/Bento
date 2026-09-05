import SwiftUI
import AppKit

/// 菜单栏面板。
///
/// Phase 0 只在面板打开时读一次剪贴板。真正的
/// `NSPasteboard.general.changeCount` 轮询 + 图标染色属于 Phase 5，
/// 那个才是决定这个 App 会不会被天天用的功能。
struct MenuBarPanel: View {
    @Environment(AppState.self) private var app
    @Environment(\.openWindow) private var openWindow

    @State private var clipboard: String = ""
    @State private var detected: ContentDetector.Hit?

    var body: some View {
        VStack(spacing: 0) {
            clipboardSection
            favoritesSection
            footer
        }
        .frame(width: Tokens.menuBarPanelW)
        .onAppear(perform: readClipboard)
    }

    // MARK: - 剪贴板

    private var clipboardSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Circle()
                    .fill(detected != nil ? Tokens.ok : Tokens.tertiaryLabel)
                    .frame(width: 7, height: 7)
                    .shadow(color: detected != nil ? Tokens.ok.opacity(0.7) : .clear, radius: 3)
                Text(detected != nil ? "剪贴板 · 已识别" : "剪贴板")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.bottom, 8)

            Text(clipboard.isEmpty ? "（空）" : clipboard)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(Tokens.cardBG, in: .rect(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Tokens.separator, lineWidth: 0.5)
                )

            if let hit = detected {
                Text(hit.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.top, 9)

                HStack(spacing: 6) {
                    if let first = hit.relatedToolNames.first,
                       let item = resolve(first) {
                        Button(item.name) { jump(item) }
                            .bentoButton(prominent: true)
                    }
                    CopyButton(value: hit.value, compact: false)
                }
                .padding(.top, 10)
            } else {
                Text("没有可直接处理的内容")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 9)
            }
        }
        .padding(13)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Tokens.separator).frame(height: 0.5)
        }
    }

    // MARK: - 收藏

    private var favoritesSection: some View {
        VStack(spacing: 1) {
            ForEach(Array(app.favoriteItems.enumerated()), id: \.element.id) { index, item in
                Button {
                    jump(item)
                } label: {
                    HStack(spacing: 10) {
                        CategoryIcon(symbol: item.symbol, tint: item.category.tint)
                        Text(item.name).font(.system(size: 13))
                        Spacer()
                        Keycap(text: "⌘\(index + 1)")
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 34)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(7)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Tokens.separator).frame(height: 0.5)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Button("打开主窗口") { activateMainWindow() }.bentoButton()
            Spacer()
            Button("退出") { NSApp.terminate(nil) }.bentoButton()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
    }

    // MARK: - 逻辑

    private func readClipboard() {
        let s = NSPasteboard.general.string(forType: .string) ?? ""
        clipboard = s.replacingOccurrences(of: "\n", with: " ")
        detected = ContentDetector.detect(s)
    }

    private func resolve(_ nameOrID: String) -> ToolItem? {
        ToolRegistry.item(id: nameOrID) ?? ToolRegistry.items.first { $0.name == nameOrID }
    }

    private func jump(_ item: ToolItem) {
        guard item.implemented else { return }
        app.select(item.id)
        activateMainWindow()
    }

    private func activateMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }
}
