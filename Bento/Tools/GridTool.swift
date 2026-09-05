import SwiftUI

struct GridTool: ToolView {
    static let meta = ToolMeta(
        id: "grid", name: "间距栅格", category: .style, layout: .canvas,
        symbol: "square.grid.3x3",
        aliases: ["grid", "spacing", "layout", "jjzg", "zhage"]
    )

    @State private var unit: Double = 8
    @State private var containerW: Double = 960
    @State private var columns: Double = 12
    @State private var gutter: Double = 24
    @State private var margin: Double = 24

    init() {}

    var body: some View {
        StackLayout(status: status) {
            OptionLabel(text: "基数")
            BentoSegments(options: [(4.0, "4pt"), (8.0, "8pt")], selection: $unit)
            Spacer()
            Text("间距刻度按基数的倍数生成")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
        } content: {
            Card(title: "栅格计算", dot: ToolCategory.style.tint, meta: gridSummary) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 16) {
                        numField("容器宽", $containerW, 320...2560)
                        numField("列数", $columns, 1...24)
                        numField("列间距", $gutter, 0...80)
                        numField("外边距", $margin, 0...120)
                        Spacer()
                    }
                    gridPreview
                }
                .padding(Tokens.padCard)
            }
            .fixedSize(horizontal: false, vertical: true)

            Card(title: "间距刻度", dot: ToolCategory.image.tint, meta: "点色块复制数值") {
                scaleStrip
            }
            .fixedSize(horizontal: false, vertical: true)

            Card(title: "代码", dot: ToolCategory.formatting.tint, meta: "3 种 · 逐行复制") {
                ResultRows(rows: codeRows, keyWidth: 96)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: - 视图

    private func numField(_ label: String, _ v: Binding<Double>,
                          _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 10)).foregroundStyle(.tertiary)
            HStack(spacing: 4) {
                TextField("", value: v, format: .number)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 7)
                    .frame(width: 58, height: 24)
                    .sunkenSurface(radius: 6)
                Stepper("", value: v, in: range, step: label == "列数" ? 1 : unit)
                    .labelsHidden()
            }
        }
    }

    private var gridPreview: some View {
        GeometryReader { geo in
            let scale = geo.size.width / containerW
            HStack(spacing: gutter * scale) {
                ForEach(0..<Int(columns), id: \.self) { _ in
                    Rectangle()
                        .fill(Tokens.accent.opacity(0.18))
                        .overlay(Rectangle().strokeBorder(Tokens.accent.opacity(0.35), lineWidth: 0.5))
                }
            }
            .padding(.horizontal, margin * scale)
            .frame(height: 56)
        }
        .frame(height: 56)
        .background(Tokens.sunkenBG, in: .rect(cornerRadius: 8))
    }

    private var scaleStrip: some View {
        let steps = scaleSteps
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(steps, id: \.0) { name, value in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Tokens.accentGradient)
                        .frame(width: max(6, min(value, 64)), height: 26)
                    Text(name).font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("\(Int(value))").font(.system(size: 10, design: .monospaced))
                }
                .contentShape(.rect)
                .onTapGesture {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("\(Int(value))", forType: .string)
                }
            }
            Spacer()
        }
        .padding(.horizontal, Tokens.padCard)
        .padding(.bottom, Tokens.padCard)
    }

    // MARK: - 计算

    /// 间距刻度：基数的 0.5×…12×，跳过太密的中间档
    private var scaleSteps: [(String, Double)] {
        let multipliers: [Double] = [0.5, 1, 1.5, 2, 3, 4, 5, 6, 8, 10, 12]
        return multipliers.map { m in
            let v = unit * m
            return ("\(m == m.rounded() ? String(Int(m)) : String(format: "%.1f", m))×", v)
        }
    }

    private var columnWidth: Double {
        let inner = containerW - margin * 2 - gutter * (columns - 1)
        return inner / columns
    }

    private var gridSummary: String {
        String(format: "列宽 %.2f pt", columnWidth)
    }

    private var codeRows: [(String, String)] {
        let steps = scaleSteps
        return [
            ("SwiftUI", "enum Spacing {\n" + steps.map {
                "    static let s\($0.0.replacingOccurrences(of: "×", with: "").replacingOccurrences(of: ".", with: "_")): CGFloat = \(Int($0.1))"
            }.joined(separator: "\n") + "\n}"),
            ("CSS", ":root {\n" + steps.map {
                "  --space-\($0.0.replacingOccurrences(of: "×", with: "")): \(Int($0.1))px;"
            }.joined(separator: "\n") + "\n}"),
            ("栅格", String(format: "容器 %g − 外边距 %g×2 − 间距 %g×%d = 内容宽 %.1f，列宽 %.2f",
                          containerW, margin, gutter, Int(columns) - 1,
                          containerW - margin * 2, columnWidth)),
        ]
    }

    private var status: StatusLine {
        if columnWidth <= 0 {
            return StatusLine(level: .error, text: "外边距和列间距之和超过了容器宽度",
                              trailing: "\(Int(unit))pt 基数", trailingKey: "⌄")
        }
        let onGrid = abs(columnWidth - (columnWidth / unit).rounded() * unit) < 0.01
        return StatusLine(
            level: onGrid ? .ok : .warning,
            text: onGrid
                ? "列宽 \(String(format: "%.2f", columnWidth)) 正好是基数的整数倍"
                : "列宽 \(String(format: "%.2f", columnWidth)) 不是 \(Int(unit)) 的整数倍 — 栅格里这通常没关系，元素内部间距对齐即可",
            trailing: "\(Int(unit))pt 基数", trailingKey: "⌄"
        )
    }
}
