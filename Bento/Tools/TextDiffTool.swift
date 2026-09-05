import SwiftUI

struct TextDiffTool: ToolView {
    static let meta = ToolMeta(
        id: "textdiff", name: "文本 Diff", category: .formatting, layout: .stacked,
        symbol: "arrow.left.arrow.right.square",
        aliases: ["diff", "compare", "wbdb", "duibi"]
    )

    // 模型和算法都在 Core/TextDiff.swift，这里只管画
    typealias Kind = TextDiff.Kind
    typealias Row = TextDiff.Row
    typealias Pair = TextDiff.Pair

    @State private var left = "let a = 1\nlet b = 2\nprint(a + b)"
    @State private var right = "let a = 1\nlet b = 20\nlet c = 3\nprint(a + b + c)"
    @State private var ignoreWhitespace = false
    @State private var ignoreCase = false
    @State private var onlyChanges = false
    @State private var splitView = true

    init() {}


    var body: some View {
        CompareLayout(
            status: status, left: $left, right: $right,
            leftMeta: "\(lines(left).count) 行", rightMeta: "\(lines(right).count) 行"
        ) {
            OptionLabel(text: "视图")
            BentoSegments(options: [(true, "并排"), (false, "统一")],
                          selection: $splitView, accent: true)
            OptionLabel(text: "忽略")
            BentoCheck(label: "空白", isOn: $ignoreWhitespace)
            BentoCheck(label: "大小写", isOn: $ignoreCase)
            Spacer()
            BentoCheck(label: "只看差异", isOn: $onlyChanges)
        } result: {
            Card(title: "差异", dot: ToolCategory.formatting.tint, meta: summary) {
                if splitView { splitBody } else { unifiedBody }
            }
        }
    }

    // MARK: - 统一视图

    private var unifiedBody: some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(spacing: 0) {
                ForEach(visibleRows) { rowView($0) }
            }
        }
        .scrollIndicators(.visible)
    }

    // MARK: - 并排视图

    /// 左右两列放在**同一个** ScrollView 里 —— 垂直和水平滚动天然同步，
    /// 不需要给两个 NSScrollView 装联动。
    private var splitBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                columnHeader("原始", count: removedCount, color: Tokens.error)
                Rectangle().fill(Tokens.separator).frame(width: 1)
                columnHeader("对比", count: addedCount, color: Tokens.ok)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Tokens.separator).frame(height: 0.5)
            }

            ScrollView([.vertical, .horizontal]) {
                HStack(alignment: .top, spacing: 0) {
                    LazyVStack(spacing: 0) {
                        ForEach(visiblePairs) { pairSide($0, side: .left) }
                    }
                    Rectangle().fill(Tokens.separator).frame(width: 1)
                    LazyVStack(spacing: 0) {
                        ForEach(visiblePairs) { pairSide($0, side: .right) }
                    }
                }
            }
            .scrollIndicators(.visible)
        }
    }

    private func columnHeader(_ title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Text("\(count) 处").font(.system(size: 10)).foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .frame(maxWidth: .infinity)
    }

    /// 列头固定在顶部不跟着横向滚动，所以这里单独给它一份等分宽度

    private enum Side { case left, right }

    @ViewBuilder
    private func pairSide(_ pair: Pair, side: Side) -> some View {
        let row = side == .left ? pair.left : pair.right
        let no = side == .left ? row?.oldNo : row?.newNo
        HStack(spacing: 0) {
            Text(no.map(String.init) ?? "")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 42, alignment: .trailing)
                .padding(.trailing, 8)
            Text(row?.text.isEmpty == false ? row!.text : " ")
                .font(Tokens.mono)
                .foregroundStyle(row == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 8)
        .frame(width: contentWidth + 50, height: 22, alignment: .leading)
        .background(sideBackground(pair, side: side))
    }

    /// 对面有行、这边没有 → 画中性灰占位，让两列始终对齐
    private func sideBackground(_ pair: Pair, side: Side) -> Color {
        let row = side == .left ? pair.left : pair.right
        guard let row else { return Tokens.tertiaryLabel.opacity(0.06) }
        switch row.kind {
        case .same:    return .clear
        case .removed: return Tokens.error.opacity(0.13)
        case .added:   return Tokens.ok.opacity(0.13)
        }
    }

    private func rowView(_ row: Row) -> some View {
        HStack(spacing: 0) {
            Text(row.oldNo.map(String.init) ?? "")
                .frame(width: 40, alignment: .trailing)
            Text(row.newNo.map(String.init) ?? "")
                .frame(width: 40, alignment: .trailing)
            Text(marker(row.kind))
                .frame(width: 22, alignment: .center)
                .foregroundStyle(color(row.kind))
            Text(row.text.isEmpty ? " " : row.text)
                .fixedSize(horizontal: true, vertical: false)
                .textSelection(.enabled)
        }
        .font(Tokens.mono)
        .foregroundStyle(row.kind == .same ? AnyShapeStyle(.primary) : AnyShapeStyle(color(row.kind)))
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(width: contentWidth + 122, height: 22, alignment: .leading)
        .background(background(row.kind))
    }

    private func marker(_ k: Kind) -> String {
        switch k {
        case .same: return " "
        case .added: return "+"
        case .removed: return "−"
        }
    }

    private func color(_ k: Kind) -> Color {
        switch k {
        case .same: return .secondary
        case .added: return Tokens.ok
        case .removed: return Tokens.error
        }
    }

    private func background(_ k: Kind) -> Color {
        switch k {
        case .same: return .clear
        case .added: return Tokens.ok.opacity(0.12)
        case .removed: return Tokens.error.opacity(0.12)
        }
    }

    // MARK: - Diff

    private func lines(_ s: String) -> [String] { s.components(separatedBy: .newlines) }

    private var options: TextDiff.Options {
        .init(ignoreWhitespace: ignoreWhitespace, ignoreCase: ignoreCase)
    }

    private var rows: [Row] {
        TextDiff.rows(old: lines(left), new: lines(right), options: options)
    }

    private var visibleRows: [Row] {
        onlyChanges ? rows.filter { $0.kind != .same } : rows
    }

    private var pairs: [Pair] { TextDiff.pairs(rows) }

    /// 横向可滚动时不能靠 Spacer / maxWidth:.infinity 撑宽 —— 宽度提案是无限的，
    /// 行为不确定。等宽字体下按最长行估算一个确定宽度，所有行统一用它，
    /// 这样背景能铺满、左右两列也严格对齐。
    private var contentWidth: CGFloat {
        let all = lines(left) + lines(right)
        // 中日韩字符按两个字宽算
        let widest = all.map { line in
            line.reduce(0) { $0 + ($1.isCJK ? 2 : 1) }
        }.max() ?? 40
        return max(300, CGFloat(widest) * 7.25 + 40)
    }

    private var visiblePairs: [Pair] {
        onlyChanges ? pairs.filter { !$0.isSame } : pairs
    }

    private var addedCount: Int { rows.filter { $0.kind == .added }.count }
    private var removedCount: Int { rows.filter { $0.kind == .removed }.count }

    private var summary: String {
        "+\(addedCount)  −\(removedCount)  ·  共 \(rows.count) 行"
    }

    private var status: StatusLine {
        if left.isEmpty && right.isEmpty {
            return StatusLine(level: .idle, text: "两侧都为空", trailing: "行级 Diff", trailingKey: "⌄")
        }
        if addedCount == 0 && removedCount == 0 {
            return StatusLine(level: .ok, text: "两侧完全一致", trailing: "行级 Diff", trailingKey: "⌄")
        }
        return StatusLine(level: .warning,
                          text: "新增 \(addedCount) 行 · 删除 \(removedCount) 行",
                          trailing: "行级 Diff", trailingKey: "⌄")
    }
}
