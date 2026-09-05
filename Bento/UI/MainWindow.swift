import SwiftUI

struct MainWindow: View {
    @Environment(AppState.self) private var app

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
            Rectangle().fill(Tokens.separator).frame(width: 0.5)
            detail
        }
        .frame(minWidth: 860, minHeight: 520)
        .overlay {
            if app.paletteOpen {
                CommandPalette()
                    .transition(.opacity)
            }
        }
        .animation(Tokens.selectAnim, value: app.paletteOpen)
        .toolbar { toolbarContent }
        .navigationTitle("")
    }

    // MARK: - 工作区

    @ViewBuilder
    private var detail: some View {
        if let entry = app.selectedEntry {
            entry.build()
                .id(entry.id)   // 切工具时重建，避免上一个工具的 @State 漏过来
        } else {
            EmptyToolView()
        }
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 10) {
                if let meta = app.selectedMeta {
                    CategoryIcon(symbol: meta.symbol, tint: meta.category.tint,
                                 size: Tokens.iconLarge)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(meta.name).font(Tokens.title)
                        Text("\(meta.category.title) · \(layoutName(meta.layout))")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }

        ToolbarItemGroup {
            Button {
                app.paletteOpen = true
            } label: {
                Keycap(text: "⌘K")
            }
            .buttonStyle(.plain)
            .help("命令面板")

            if let id = app.selectedToolID {
                Button {
                    app.toggleFavorite(id)
                } label: {
                    Image(systemName: app.isFavorite(id) ? "star.fill" : "star")
                        .foregroundStyle(app.isFavorite(id) ? Color(nsColor: .systemYellow)
                                                            : Color.secondary)
                }
                .help(app.isFavorite(id) ? "取消收藏" : "收藏")
            }

            Menu {
                Text("工具选项将在 Phase 7 补齐")
            } label: {
                Image(systemName: "ellipsis")
            }
        }
    }

    private func layoutName(_ l: ToolLayout) -> String {
        switch l {
        case .dual:    return ".dual"
        case .stacked: return ".stacked"
        case .form:    return ".form"
        case .canvas:  return ".canvas"
        }
    }
}
