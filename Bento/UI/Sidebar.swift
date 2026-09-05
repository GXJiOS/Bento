import SwiftUI

struct Sidebar: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app

        VStack(spacing: 0) {
            // 搜索
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                TextField("搜索工具", text: $app.sidebarQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                if app.sidebarQuery.isEmpty {
                    Keycap(text: "⌘F")
                } else {
                    Button {
                        app.sidebarQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 29)
            .sunkenSurface(radius: 8)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            // 工具树
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if app.sidebarQuery.isEmpty {
                            pinnedSection("收藏", symbol: "star.fill",
                                          tint: Color(nsColor: .systemYellow),
                                          items: app.favoriteItems, shortcuts: true)
                            ForEach(ToolCategory.allCases) { category in
                                categorySection(category)
                            }
                        } else {
                            searchResults
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.never)
                .onChange(of: app.selectedToolID) { _, id in
                    // 只在需要时滚动；SwiftUI 的 scrollTo 本身会判断可见性
                    guard let id else { return }
                    withAnimation(Tokens.selectAnim) { proxy.scrollTo(id, anchor: .center) }
                }
            }

            // 底部统计（当进度条用）
            HStack(spacing: 7) {
                Circle().fill(Tokens.ok).frame(width: 7, height: 7)
                Text("\(ToolRegistry.implementedCount) 个工具"
                     + (app.hidden.isEmpty ? "" : " · \(app.hidden.count) 个已隐藏"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .overlay(alignment: .top) {
                Rectangle().fill(Tokens.separator).frame(height: 0.5)
            }
        }
        .frame(width: Tokens.sidebarW)
        .background(.bar)
    }

    // MARK: - 分区

    @ViewBuilder
    private func pinnedSection(_ title: String, symbol: String, tint: Color,
                               items: [ToolItem], shortcuts: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: title, symbol: symbol, tint: tint, count: nil, expanded: true) {}
            VStack(spacing: 1) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    row(item, shortcut: shortcuts && index < 9 ? "⌘\(index + 1)" : nil)
                }
            }
            .padding(.leading, 31)
            .padding(.top, 2)
        }
        .padding(.top, 11)
    }

    @ViewBuilder
    private func categorySection(_ category: ToolCategory) -> some View {
        let isOpen = app.expanded.contains(category)
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: category.title, symbol: category.symbol, tint: category.tint,
                          count: app.visibleItems(in: category).count, expanded: isOpen) {
                withAnimation(Tokens.selectAnim) { app.toggleCategory(category) }
            }
            if isOpen {
                VStack(spacing: 1) {
                    ForEach(app.visibleItems(in: category)) { row($0, shortcut: nil) }
                }
                .padding(.leading, 31)
                .padding(.top, 2)
            }
        }
        .padding(.top, 11)
    }

    private func sectionHeader(title: String, symbol: String, tint: Color,
                               count: Int?, expanded: Bool,
                               toggle: @escaping () -> Void) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .frame(width: 8)
            CategoryIcon(symbol: symbol, tint: tint)
            Text(title).font(Tokens.sidebarSection)
            Spacer(minLength: 4)
            if let count {
                Text("\(count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 2)
        .frame(height: Tokens.sectionH)
        .contentShape(.rect)
        .onTapGesture(perform: toggle)
    }

    // MARK: - 行

    @ViewBuilder
    private func row(_ item: ToolItem, shortcut: String?) -> some View {
        let selected = app.selectedToolID == item.id
        HStack(spacing: 7) {
            Text(item.name)
                .font(Tokens.body)
                .foregroundStyle(selected ? AnyShapeStyle(Color.white)
                                          : AnyShapeStyle(item.implemented ? .primary : .secondary))
                .lineLimit(1)
            Spacer(minLength: 4)
            if let shortcut {
                Keycap(text: shortcut)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: Tokens.itemH)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Tokens.accentGradient)
                    .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
            }
        }
        .contentShape(.rect)
        .onTapGesture { app.select(item.id) }
        .id(item.id)
        .help(item.implemented ? item.name : "\(item.name) — 路线图上，尚未实现")
    }

    // MARK: - 搜索结果

    private var searchResults: some View {
        let results = app.search(app.sidebarQuery)
        return VStack(alignment: .leading, spacing: 1) {
            if results.isEmpty {
                Text("没有匹配的工具")
                    .font(Tokens.small)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 9)
            } else {
                ForEach(results) { item in
                    HStack(spacing: 9) {
                        CategoryIcon(symbol: item.symbol, tint: item.category.tint, size: 18)
                        row(item, shortcut: nil)
                    }
                }
            }
        }
        .padding(.top, 8)
    }
}
