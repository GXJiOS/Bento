import SwiftUI

/// 可展开收起的 JSON 树。
///
/// 和「JSON 工具箱」的区别：那个是文本进文本出，这个是拿来**浏览**大块 JSON 的 ——
/// 折叠掉不关心的分支，只看当前需要的那一段。
struct JSONTreeTool: ToolView {
    static let meta = ToolMeta(
        id: "jsontree", name: "JSON 树", category: .formatting, layout: .stacked,
        symbol: "list.triangle",
        aliases: ["tree", "jsontree", "outline", "fold", "shu", "jsonshu", "zhankai"]
    )

    private static let sample = """
        {
          "code": 0,
          "data": {
            "user": {
              "id": 1024, "name": "gxj", "vip": true, "avatar": null,
              "tags": ["swift", "flutter", "macos"],
              "profile": { "city": "洛阳", "score": 98.5, "joined": "2021-03-14" }
            },
            "orders": [
              { "no": "A1", "amount": 12.5, "paid": true,
                "items": [{ "sku": "X-1", "qty": 2 }, { "sku": "X-2", "qty": 1 }] },
              { "no": "A2", "amount": 30, "paid": false, "items": [] }
            ]
          },
          "ts": 1735689600
        }
        """

    @Environment(AppState.self) private var app

    @State private var input = JSONTreeTool.sample
    @State private var expanded: Set<String> = []
    @State private var filter = ""
    @State private var hovered: String?
    @State private var parsed: Result<JSONTree.Node, JSONTree.ParseError>?
    @State private var didInit = false

    init() {}

    var body: some View {
        StackLayout(status: status) {
            OptionLabel(text: "展开")
            Button("全部") { setExpanded(all: true) }.bentoButton()
            Button("收起") { setExpanded(all: false) }.bentoButton()
            ForEach([1, 2, 3], id: \.self) { n in
                Button("\(n) 层") { expandTo(n) }.bentoButton(plain: true)
            }
            Divider().frame(height: 18)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                TextField("搜索键或值", text: $filter)
                    .textFieldStyle(.plain).font(.system(size: 12))
                if !filter.isEmpty {
                    Button { filter = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .frame(width: 190, height: 26)
            .sunkenSurface(radius: 7)
            Spacer()
        } content: {
            HStack(alignment: .top, spacing: Tokens.gapCard) {
                Card(title: "JSON", dot: ToolCategory.formatting.tint,
                     meta: "\(input.count) 字符") {
                    CodeArea(text: $input, placeholder: "粘贴 JSON…")
                    CardFooter {
                        Button("粘贴") {
                            input = NSPasteboard.general.string(forType: .string) ?? input
                        }.bentoButton(plain: true)
                        Button("清空") { input = "" }.bentoButton(plain: true)
                        Spacer()
                        Button("示例") { input = Self.sample }.bentoButton(plain: true)
                    }
                }
                .frame(width: 330)

                Card(title: "树", dot: ToolCategory.image.tint, meta: treeMeta) {
                    treeBody
                }
            }
        }
        .onAppear {
            reparse()
            if !didInit {
                didInit = true
                expandTo(2)   // 默认展开两层：能看到结构，又不至于刷屏
            }
        }
        .onChange(of: input) { _, _ in reparse() }
    }

    // MARK: - 树

    @ViewBuilder
    private var treeBody: some View {
        switch parsed {
        case .success(let root):
            let rows = JSONTree.flatten(root, expanded: expanded, filter: filter)
            if rows.isEmpty {
                placeholder("没有匹配「\(filter)」的键或值")
            } else {
                // 只做垂直滚动。之前同时开横向滚动，行内的 Spacer 在「宽度无限」
                // 的提案下会把内容整个推走，布局直接错乱 —— 长值改成截断处理。
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row($0) }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.automatic)
            }
        case .failure(let error):
            placeholder(error.isEmpty ? "粘贴 JSON 后在这里浏览" : error.message,
                        isError: !error.isEmpty)
        case nil:
            placeholder("…")
        }
    }

    private func placeholder(_ text: String, isError: Bool = false) -> some View {
        Text(text)
            .font(Tokens.body)
            .foregroundStyle(styleIf(isError, Tokens.error, .secondary))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(Tokens.padCard)
    }

    private func row(_ r: JSONTree.Row) -> some View {
        let node = r.node
        let isHovered = hovered == node.path
        return HStack(spacing: 5) {
            // 展开箭头。标量没有箭头，但要占同样的宽度才能和容器行对齐。
            // 这里必须给足宽高约束 —— 裸的 Color 是无限尺寸视图，
            // 只写 .frame(width:) 会让它在垂直方向撑爆行高。
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(r.expanded ? 90 : 0))
                .opacity(node.kind.isContainer && node.kind.childCount > 0 ? 1 : 0)
                .frame(width: 11, height: 22)

            Text(node.label)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(node.index != nil ? AnyShapeStyle(.tertiary)
                                                   : AnyShapeStyle(.primary))

            if node.kind.isContainer {
                // 收起时给出「{ N 项 }」；展开了就不重复显示，让子行自己说话
                if !r.expanded || node.kind.childCount == 0 {
                    Text(node.kind.collapsedSummary)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(":")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Text(node.kind.display)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(color(for: node.kind))
                    .lineLimit(1)
            }

            if isHovered {
                Spacer(minLength: 12)
                Text(node.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Button("路径") { copy(node.path) }.bentoButton(plain: true)
                Button(node.kind.isContainer ? "子树" : "值") {
                    copy(node.kind.isContainer ? JSONTree.json(node) : node.kind.rawValue)
                }
                .bentoButton(plain: true)
            }
        }
        // 缩进用 padding，不再拿占位视图撑
        .padding(.leading, Tokens.padCard + CGFloat(node.depth) * 15)
        .padding(.trailing, Tokens.padCard)
        .frame(height: 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovered ? Tokens.cardHoverBG : .clear)
        .contentShape(.rect)
        .onHover { hovered = $0 ? node.path : (hovered == node.path ? nil : hovered) }
        .onTapGesture { toggle(node) }
    }

    /// 类型着色 —— 一眼区分 string / number / bool / null
    private func color(for kind: JSONTree.Kind) -> Color {
        switch kind {
        case .string: return ToolCategory.image.tint      // 绿
        case .number: return ToolCategory.encoding.tint   // 蓝
        case .bool:   return ToolCategory.formatting.tint // 紫
        case .null:   return Tokens.tertiaryLabel
        default:      return .secondary
        }
    }

    // MARK: - 操作

    private func reparse() {
        parsed = JSONTree.parse(input)
    }

    private func toggle(_ node: JSONTree.Node) {
        guard node.kind.isContainer, node.kind.childCount > 0 else { return }
        if expanded.contains(node.path) { expanded.remove(node.path) }
        else { expanded.insert(node.path) }
    }

    private func setExpanded(all: Bool) {
        guard case .success(let root) = parsed else { return }
        expanded = all ? JSONTree.allContainerPaths(root) : []
    }

    private func expandTo(_ depth: Int) {
        guard case .success(let root) = parsed else { return }
        expanded = JSONTree.paths(root, upTo: depth)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: -

    private var treeMeta: String {
        guard case .success(let root) = parsed else { return "—" }
        let s = JSONTree.stats(root)
        let visible = JSONTree.flatten(root, expanded: expanded, filter: filter).count
        return "\(visible) / \(s.nodes) 行"
    }

    private var status: StatusLine {
        switch parsed {
        case .success(let root):
            let s = JSONTree.stats(root)
            if !filter.isEmpty {
                let hits = JSONTree.flatten(root, expanded: expanded, filter: filter).count
                return StatusLine(level: hits > 0 ? .ok : .warning,
                                  text: hits > 0 ? "「\(filter)」命中 \(hits) 行 · 命中路径已自动展开"
                                                 : "没有匹配「\(filter)」的键或值",
                                  trailing: "点行展开 / 收起", trailingKey: "⌄")
            }
            return StatusLine(level: .ok,
                              text: "\(s.nodes) 节点 · \(s.objects) 对象 · \(s.arrays) 数组 · "
                                  + "\(s.scalars) 标量 · 最深 \(s.maxDepth) 层",
                              trailing: "点行展开 / 收起", trailingKey: "⌄")
        case .failure(let e):
            return e.isEmpty
                ? StatusLine(level: .idle, text: "粘贴 JSON", trailing: "树视图", trailingKey: "⌄")
                : StatusLine(level: .error, text: e.message, trailing: "树视图", trailingKey: "⌄")
        case nil:
            return StatusLine(level: .idle, text: "…", trailing: "树视图", trailingKey: "⌄")
        }
    }
}
