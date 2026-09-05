import SwiftUI

struct UnitTool: ToolView {
    static let meta = ToolMeta(
        id: "unit", name: "单位换算", category: .style, layout: .form,
        symbol: "ruler",
        aliases: ["unit", "px", "pt", "rem", "dp", "dwhs", "danwei"]
    )

    enum Unit: Hashable, CaseIterable {
        case pt, px, rem, em, vw, vh, dp, inch, mm

        var label: String {
            switch self {
            case .pt: return "pt"
            case .px: return "px"
            case .rem: return "rem"
            case .em: return "em"
            case .vw: return "vw"
            case .vh: return "vh"
            case .dp: return "dp"
            case .inch: return "in"
            case .mm: return "mm"
            }
        }
    }

    @State private var value: Double = 16
    @State private var unit: Unit = .pt
    @State private var rootSize: Double = 16
    @State private var parentSize: Double = 16
    @State private var viewportW: Double = 1440
    @State private var viewportH: Double = 900

    init() {}

    var body: some View {
        StackLayout(status: status) {
            OptionLabel(text: "输入单位")
            BentoSegments(options: Array(Unit.allCases.prefix(5)).map { ($0, $0.label) },
                          selection: $unit)
            BentoSegments(options: Array(Unit.allCases.suffix(4)).map { ($0, $0.label) },
                          selection: $unit)
            Spacer()
        } content: {
            Card {
                HStack(spacing: 16) {
                    TextField("", value: $value, format: .number)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18, design: .monospaced))
                        .padding(.horizontal, 10)
                        .frame(width: 120, height: 36)
                        .sunkenSurface(radius: 8)
                    Text(unit.label).font(.system(size: 15)).foregroundStyle(.secondary)
                    Divider().frame(height: 30)
                    basisField("根字号", $rootSize)
                    basisField("父字号", $parentSize)
                    basisField("视口宽", $viewportW)
                    basisField("视口高", $viewportH)
                    Spacer()
                }
                .padding(Tokens.padCard)
            }
            .fixedSize(horizontal: false, vertical: true)

            Card(title: "换算结果", dot: ToolCategory.style.tint, meta: "以 CSS px 为中间量") {
                ResultRows(rows: rows, keyWidth: 132)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private func basisField(_ label: String, _ binding: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 10)).foregroundStyle(.tertiary)
            TextField("", value: binding, format: .number)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 7)
                .frame(width: 62, height: 24)
                .sunkenSurface(radius: 6)
        }
    }

    // MARK: - 换算

    /// 统一折算成 CSS px（= @1x 逻辑像素 = iOS/macOS 的 pt），再从它换算到其它单位
    private var px: Double {
        switch unit {
        case .pt, .px, .dp: return value          // 三者在 @1x 下等价
        case .rem:  return value * rootSize
        case .em:   return value * parentSize
        case .vw:   return value / 100 * viewportW
        case .vh:   return value / 100 * viewportH
        case .inch: return value * 96             // CSS 定义 1in = 96px
        case .mm:   return value * 96 / 25.4
        }
    }

    private var rows: [(String, String)] {
        func f(_ v: Double) -> String {
            if v == v.rounded() { return String(Int(v)) }
            return String(format: "%.4g", v)
        }
        return [
            ("pt · iOS / macOS", "\(f(px))"),
            ("px · CSS @1x", "\(f(px))"),
            ("dp · Android", "\(f(px))    // 与 pt 在同一物理尺寸下近似相等"),
            ("rem", "\(f(px / rootSize))    // 根字号 \(f(rootSize))"),
            ("em", "\(f(px / parentSize))    // 父字号 \(f(parentSize))"),
            ("vw", "\(f(px / viewportW * 100))    // 视口宽 \(f(viewportW))"),
            ("vh", "\(f(px / viewportH * 100))    // 视口高 \(f(viewportH))"),
            ("物理像素 @2x", "\(f(px * 2)) px"),
            ("物理像素 @3x", "\(f(px * 3)) px"),
            ("英寸 / 毫米", "\(f(px / 96)) in    ·    \(f(px / 96 * 25.4)) mm"),
            ("最近 4pt 网格", "\(f((px / 4).rounded() * 4))    差 \(f(abs(px - (px / 4).rounded() * 4)))"),
            ("最近 8pt 网格", "\(f((px / 8).rounded() * 8))    差 \(f(abs(px - (px / 8).rounded() * 8)))"),
        ]
    }

    private var status: StatusLine {
        let onGrid4 = abs(px - (px / 4).rounded() * 4) < 0.01
        let onGrid8 = abs(px - (px / 8).rounded() * 8) < 0.01
        let grid = onGrid8 ? "正好落在 8pt 网格" : (onGrid4 ? "落在 4pt 网格" : "不在 4/8pt 网格上")
        return StatusLine(level: onGrid4 ? .ok : .warning,
                          text: "\(String(format: "%g", px)) px · \(grid)",
                          trailing: "1in = 96px", trailingKey: "⌄")
    }
}
