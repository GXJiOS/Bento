import SwiftUI

struct GradientTool: ToolView {
    static let meta = ToolMeta(
        id: "gradient", name: "渐变生成", category: .style, layout: .canvas,
        symbol: "circle.lefthalf.striped.horizontal",
        aliases: ["gradient", "linear", "jb", "jianbian"]
    )

    enum Kind: Hashable, CaseIterable {
        case linear, radial, angular
        var label: String {
            switch self {
            case .linear: return "线性"
            case .radial: return "径向"
            case .angular: return "角向"
            }
        }
    }

    struct Stop: Identifiable {
        let id = UUID()
        var hex: String
        var location: Double     // 0...1
    }

    @State private var stops: [Stop] = [
        Stop(hex: "#4A90D9", location: 0),
        Stop(hex: "#AF52DE", location: 1),
    ]
    @State private var kind: Kind = .linear
    @State private var angle: Double = 135

    init() {}

    var body: some View {
        StackLayout(status: status) {
            OptionLabel(text: "类型")
            BentoSegments(options: Kind.allCases.map { ($0, $0.label) }, selection: $kind)
            Spacer()
            Button {
                addStop()
            } label: {
                HStack(spacing: 4) { Image(systemName: "plus"); Text("加色标") }
            }
            .bentoButton(prominent: true)
            Button("反转") { reverse() }.bentoButton()
        } content: {
            Card {
                HStack(alignment: .top, spacing: 20) {
                    preview
                    controls
                }
                .padding(Tokens.padCard)
            }
            .fixedSize(horizontal: false, vertical: true)

            Card(title: "代码输出", dot: ToolCategory.style.tint, meta: "3 种 · 逐行复制") {
                ResultRows(rows: codeRows, keyWidth: 108)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: - 预览

    private var preview: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(shapeStyle)
            .frame(width: 250, height: 190)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Tokens.separator, lineWidth: 0.5)
            )
    }

    private var shapeStyle: AnyShapeStyle {
        let g = Gradient(stops: stops.sorted { $0.location < $1.location }.map {
            Gradient.Stop(color: swiftColor($0.hex), location: $0.location)
        })
        switch kind {
        case .linear:
            let r = angle * .pi / 180
            // CSS 角度 0° 朝上、顺时针；SwiftUI 用起止点表达
            let dx = sin(r) / 2, dy = -cos(r) / 2
            return AnyShapeStyle(LinearGradient(
                gradient: g,
                startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
                endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy)))
        case .radial:
            return AnyShapeStyle(RadialGradient(gradient: g, center: .center,
                                                startRadius: 0, endRadius: 125))
        case .angular:
            return AnyShapeStyle(AngularGradient(gradient: g, center: .center))
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if kind == .linear {
                HStack(spacing: 8) {
                    Text("角度").font(.system(size: 12)).foregroundStyle(.secondary)
                    Slider(value: $angle, in: 0...360, step: 1)
                    Text("\(Int(angle))°").font(Tokens.mono).monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
                HStack(spacing: 5) {
                    ForEach([0, 45, 90, 135, 180, 270], id: \.self) { a in
                        Button("\(a)°") { angle = Double(a) }.bentoButton(plain: true)
                    }
                }
            }
            Divider()
            ScrollView {
                VStack(spacing: 8) {
                    ForEach($stops) { $stop in
                        StopEditor(stop: $stop, canDelete: stops.count > 2) {
                            stops.removeAll { $0.id == stop.id }
                        }
                    }
                }
            }
            .frame(maxHeight: 150)
            .scrollIndicators(.never)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 操作

    private func addStop() {
        let sorted = stops.sorted { $0.location < $1.location }
        // 插在最大的空隙中间，而不是固定加在末尾
        var bestGap = (index: 0, size: -1.0)
        for i in 0..<(sorted.count - 1) {
            let gap = sorted[i + 1].location - sorted[i].location
            if gap > bestGap.size { bestGap = (i, gap) }
        }
        let mid = (sorted[bestGap.index].location + sorted[bestGap.index + 1].location) / 2
        let a = ColorMath.parse(sorted[bestGap.index].hex) ?? ColorMath.RGB(r: 0, g: 0, b: 0)
        let b = ColorMath.parse(sorted[bestGap.index + 1].hex) ?? ColorMath.RGB(r: 1, g: 1, b: 1)
        stops.append(Stop(hex: ColorMath.mix(a, b, 0.5).hex, location: mid))
    }

    private func reverse() {
        for i in stops.indices { stops[i].location = 1 - stops[i].location }
    }

    private func swiftColor(_ hex: String) -> Color {
        guard let c = ColorMath.parse(hex) else { return .gray }
        return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
    }

    // MARK: - 输出

    private var sorted: [Stop] { stops.sorted { $0.location < $1.location } }

    private var codeRows: [(String, String)] {
        [("CSS", cssValue), ("SwiftUI", swiftValue), ("色标", stopsSummary)]
    }

    private var cssValue: String {
        let list = sorted.map { s -> String in
            let hex = (ColorMath.parse(s.hex)?.hex ?? s.hex).lowercased()
            return "\(hex) \(Int(s.location * 100))%"
        }.joined(separator: ", ")
        switch kind {
        case .linear:  return "background: linear-gradient(\(Int(angle))deg, \(list));"
        case .radial:  return "background: radial-gradient(circle, \(list));"
        case .angular: return "background: conic-gradient(from 0deg, \(list));"
        }
    }

    private var swiftValue: String {
        let list = sorted.map { s -> String in
            guard let c = ColorMath.parse(s.hex) else { return "" }
            return String(format: ".init(color: Color(.sRGB, red: %.3f, green: %.3f, blue: %.3f, opacity: 1), location: %.2f)",
                          c.r, c.g, c.b, s.location)
        }.joined(separator: ", ")
        switch kind {
        case .linear:
            let r = angle * .pi / 180
            let dx = sin(r) / 2, dy = -cos(r) / 2
            return String(format: "LinearGradient(stops: [%@], startPoint: UnitPoint(x: %.2f, y: %.2f), endPoint: UnitPoint(x: %.2f, y: %.2f))",
                          list, 0.5 - dx, 0.5 - dy, 0.5 + dx, 0.5 + dy)
        case .radial:
            return "RadialGradient(stops: [\(list)], center: .center, startRadius: 0, endRadius: 125)"
        case .angular:
            return "AngularGradient(stops: [\(list)], center: .center)"
        }
    }

    private var stopsSummary: String {
        sorted.map { "\($0.hex) @ \(Int($0.location * 100))%" }.joined(separator: "  →  ")
    }

    private var status: StatusLine {
        let bad = stops.filter { ColorMath.parse($0.hex) == nil }
        if !bad.isEmpty {
            return StatusLine(level: .error, text: "\(bad.count) 个色标的颜色无法解析",
                              trailing: kind.label, trailingKey: "⌄")
        }
        var hint = "\(stops.count) 个色标"
        if kind == .linear {
            hint += " · CSS 角度 0° 朝上顺时针，已换算成 SwiftUI 的起止点"
        }
        return StatusLine(level: .ok, text: hint, trailing: kind.label, trailingKey: "⌄")
    }
}

private struct StopEditor: View {
    @Binding var stop: GradientTool.Stop
    let canDelete: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ColorField(label: "", hex: $stop.hex, size: 22, showSampler: false)
                .frame(width: 150)
            Slider(value: $stop.location, in: 0...1)
            Text("\(Int(stop.location * 100))%")
                .font(.system(size: 11, design: .monospaced))
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
            Button { onDelete() } label: { Image(systemName: "trash") }
                .bentoButton(plain: true)
                .disabled(!canDelete)
        }
        .padding(7)
        .background(Tokens.sunkenBG, in: .rect(cornerRadius: 8))
    }
}
