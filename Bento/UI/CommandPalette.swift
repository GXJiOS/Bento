import SwiftUI
import AppKit

/// 命令面板的窗口内 overlay 形态（⌘K）。
/// 全局 ⌥Space 唤起的独立 NSPanel 用同一个 `PaletteContent`，见 PalettePanel.swift。
struct CommandPalette: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { app.paletteOpen = false }

            PaletteContent()
                .padding(.top, 90)
        }
    }
}

/// 面板本体。不含遮罩和定位，方便被 overlay 与独立面板复用。
struct PaletteContent: View {
    @Environment(AppState.self) private var app
    @FocusState private var focused: Bool
    /// 独立面板里回车后要关掉整个 panel，overlay 里只需要清状态
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        @Bindable var app = app

        Group {
            VStack(spacing: 0) {
                // 输入
                HStack(spacing: 13) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.tertiary)
                    TextField("搜索工具，或直接粘贴内容…", text: $app.paletteQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 21))
                        .focused($focused)
                        .onSubmit { openFirst() }
                    Keycap(text: "esc")
                }
                .padding(.horizontal, 20)
                .frame(height: Tokens.paletteInputH)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Tokens.separator).frame(height: 0.5)
                }

                // inline 直出
                if let hit = inlineHit {
                    inlineCard(hit)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Tokens.separator).frame(height: 0.5)
                        }
                }

                // 候选
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if results.isEmpty {
                            emptyHint
                        } else {
                            ForEach(Array(results.enumerated()), id: \.element.0.id) { index, pair in
                                resultRow(pair.0, note: pair.1, selected: index == 0)
                            }
                        }
                    }
                    .padding(7)
                }
                .scrollIndicators(.never)
                .frame(maxHeight: 250)

                // 底栏
                HStack(spacing: 9) {
                    Text("剪贴板").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(clipboardPreview)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .frame(maxWidth: 260, alignment: .leading)
                    Spacer()
                    Keycap(text: "↩"); Text("打开").font(.system(size: 11)).foregroundStyle(.secondary)
                    Keycap(text: "⌘C"); Text("复制").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .frame(height: 38)
                .overlay(alignment: .top) {
                    Rectangle().fill(Tokens.separator).frame(height: 0.5)
                }
            }
            .frame(width: Tokens.paletteW)
            .background(.regularMaterial, in: .rect(cornerRadius: Tokens.paletteRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.paletteRadius, style: .continuous)
                    .strokeBorder(Tokens.separator, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.45), radius: 30, y: 14)
        }
        .onAppear {
            focused = true
            if app.paletteQuery.isEmpty, let clip = NSPasteboard.general.string(forType: .string) {
                // 剪贴板续接：内容能被识别就直接填进去
                if ContentDetector.detect(clip) != nil {
                    app.paletteQuery = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
    }

    // MARK: - inline 结果

    private func inlineCard(_ hit: ContentDetector.Hit) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 11) {
                if let hex = hit.swatchHex, let c = ColorMath.parse(hex) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1))
                        .frame(width: 15, height: 15)
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(.black.opacity(0.2), lineWidth: 0.5))
                } else {
                    Image(systemName: hit.symbol)
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.accent)
                        .frame(width: 18)
                }
                Text(hit.value)
                    .font(.system(size: 16, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                CopyButton(value: hit.value)
            }
            Text(hit.detail)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .padding(.leading, 29)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Tokens.cardBG, in: .rect(cornerRadius: 10))
        .overlay(alignment: .leading) {
            Rectangle().fill(Tokens.accentGradient).frame(width: 3)
                .clipShape(.rect(topLeadingRadius: 10, bottomLeadingRadius: 10))
        }
        .padding(12)
    }

    private var emptyHint: some View {
        HStack(spacing: 6) {
            Text("没有匹配的工具 — 试试").font(.system(size: 12)).foregroundStyle(.tertiary)
            Keycap(text: "b64"); Keycap(text: "ysh")
            Keycap(text: "#4A90D9"); Keycap(text: "1735689600")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 14)
    }

    private func resultRow(_ item: ToolItem, note: String, selected: Bool) -> some View {
        HStack(spacing: 11) {
            CategoryIcon(symbol: item.symbol, tint: item.category.tint, selected: selected)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 13.5))
                    .foregroundStyle(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(selected ? AnyShapeStyle(Color.white.opacity(0.75))
                                              : AnyShapeStyle(.tertiary))
            }
            Spacer()
            if selected { Keycap(text: "↩") }
        }
        .padding(.horizontal, 11)
        .frame(height: Tokens.paletteRowH)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Tokens.accentGradient)
            }
        }
        .contentShape(.rect)
        .onTapGesture { open(item) }
    }

    // MARK: - 逻辑

    private var results: [(ToolItem, String)] {
        let q = app.paletteQuery.trimmingCharacters(in: .whitespaces)
        var out: [(ToolItem, String)] = []
        var seen = Set<String>()

        // inline 命中时：首项「直接打开」，其后是该内容类型的相关工具
        if let hit = inlineHit {
            for (i, id) in hit.relatedToolNames.enumerated() {
                if let item = ToolRegistry.item(id: id) ?? ToolRegistry.items.first(where: { $0.name == id }) {
                    out.append((item, i == 0 ? "直接打开" : "相关工具"))
                    seen.insert(item.id)
                }
            }
        }
        for item in app.search(q) where !seen.contains(item.id) {
            out.append((item, item.implemented ? item.category.title : "路线图 · 未实现"))
        }
        return Array(out.prefix(5))
    }

    private var inlineHit: ContentDetector.Hit? {
        ContentDetector.detect(app.paletteQuery)
    }

    private var clipboardPreview: String {
        let s = NSPasteboard.general.string(forType: .string) ?? "（空）"
        return String(s.prefix(60)).replacingOccurrences(of: "\n", with: " ")
    }

    private func openFirst() {
        if let first = results.first { open(first.0) }
    }

    private func open(_ item: ToolItem) {
        guard item.implemented else { return }
        app.select(item.id)
        app.paletteOpen = false
        app.paletteQuery = ""
        onDismiss?()
    }

}
