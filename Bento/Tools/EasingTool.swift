import SwiftUI

/// 模板 ④ .canvas 的样板工具 —— 四个模板里最重的一个
struct EasingTool: ToolView {
    static let meta = ToolMeta(
        id: "easing",
        name: "缓动曲线",
        category: .style,
        layout: .canvas,
        symbol: "chart.line.uptrend.xyaxis",
        aliases: ["easing", "bezier", "cubic", "cbz", "hdqx", "huandong"]
    )

    private static let presets: [(String, [Double])] = [
        ("ease", [0.25, 0.1, 0.25, 1]),
        ("ease-in-out", [0.42, 0, 0.58, 1]),
        ("ease-out", [0, 0, 0.58, 1]),
        ("linear", [0, 0, 1, 1]),
        ("弹入", [0.34, 1.56, 0.64, 1]),
    ]

    private static let side: CGFloat = 250
    private static let pad: CGFloat = 28

    @State private var bz: [Double] = [0.42, 0, 0.58, 1]
    @State private var duration: Double = 400
    @State private var looping = true
    @State private var dragging: Int? = nil

    init() {}

    var body: some View {
        StackLayout(status: status) {
            OptionLabel(text: "预设")
            ForEach(Self.presets, id: \.0) { name, v in
                Button(name) { bz = v }.bentoButton()
            }
            Spacer()
            BentoCheck(label: "循环播放", isOn: $looping)
        } content: {
            Card {
                HStack(alignment: .top, spacing: 18) {
                    curveCanvas
                    controls
                }
                .padding(Tokens.padCard)
            }
            .fixedSize(horizontal: false, vertical: true)

            Card(title: "代码输出", dot: ToolCategory.style.tint, meta: "4 种 · 逐行复制") {
                ResultRows(rows: codeRows, keyWidth: 118)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: - 画布

    private var curveCanvas: some View {
        Canvas { ctx, _ in draw(&ctx) }
            .frame(width: Self.side, height: Self.side)
            .sunkenSurface()
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragging == nil { dragging = hitTest(value.startLocation) }
                        guard let i = dragging else { return }
                        let n = toNormalized(value.location)
                        bz[i] = min(1, max(0, n.x))
                        bz[i + 1] = min(2, max(-1, n.y))
                    }
                    .onEnded { _ in dragging = nil }
            )
    }

    private func draw(_ ctx: inout GraphicsContext) {
        let sep = Color(nsColor: .separatorColor)
        let faint = Color(nsColor: .tertiaryLabelColor)

        // 网格
        var grid = Path()
        for i in 0...4 {
            let p = Self.pad + inner * CGFloat(i) / 4
            grid.move(to: CGPoint(x: Self.pad, y: p))
            grid.addLine(to: CGPoint(x: Self.pad + inner, y: p))
            grid.move(to: CGPoint(x: p, y: Self.pad))
            grid.addLine(to: CGPoint(x: p, y: Self.pad + inner))
        }
        ctx.stroke(grid, with: .color(sep), lineWidth: 1)

        // 对角参考线
        var diag = Path()
        diag.move(to: toPixel(0, 0))
        diag.addLine(to: toPixel(1, 1))
        ctx.stroke(diag, with: .color(faint), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))

        // 控制柄
        var handles = Path()
        handles.move(to: toPixel(0, 0))
        handles.addLine(to: toPixel(bz[0], bz[1]))
        handles.move(to: toPixel(1, 1))
        handles.addLine(to: toPixel(bz[2], bz[3]))
        ctx.stroke(handles, with: .color(faint), lineWidth: 1.2)

        // 曲线（accent → 紫的渐变描边）
        var curve = Path()
        for i in 0...110 {
            let t = Double(i) / 110
            let pt = toPixel(t, bezierY(t))
            if i == 0 { curve.move(to: pt) } else { curve.addLine(to: pt) }
        }
        ctx.stroke(
            curve,
            with: .linearGradient(
                Gradient(colors: [.accentColor, Color(nsColor: .systemPurple)]),
                startPoint: toPixel(0, 0), endPoint: toPixel(1, 1)
            ),
            style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
        )

        // 端点
        for (x, y) in [(0.0, 0.0), (1.0, 1.0)] {
            let c = toPixel(x, y)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)),
                     with: .color(Color(nsColor: .secondaryLabelColor)))
        }

        // 控制点：P1 accent / P2 紫
        for (i, color) in [(0, Color.accentColor), (2, Color(nsColor: .systemPurple))] {
            let c = toPixel(bz[i], bz[i + 1])
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14)),
                     with: .color(color))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2.4, y: c.y - 2.4, width: 4.8, height: 4.8)),
                     with: .color(.white))
        }
    }

    // MARK: - 右侧参数

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("cubic-bezier(\(fmt(bz)))")
                .font(.system(size: 13, design: .monospaced))
                .textSelection(.enabled)

            // 预览轨道
            GeometryReader { geo in
                TimelineView(.animation(paused: !looping)) { timeline in
                    let progress = ballProgress(timeline.date)
                    Circle()
                        .fill(Tokens.accentGradient)
                        .frame(width: 20, height: 20)
                        .shadow(color: Color.accentColor.opacity(0.4), radius: 5)
                        .offset(x: (geo.size.width - 20) * progress,
                                y: (geo.size.height - 20) / 2)
                }
            }
            .frame(height: 44)
            .sunkenSurface()

            HStack(spacing: 10) {
                Text("时长").font(.system(size: 12)).foregroundStyle(.secondary)
                Slider(value: $duration, in: 120...1600, step: 20)
                Text("\(Int(duration)) ms")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 54, alignment: .trailing)
            }

            Text("拖拽画布上的两个控制点\nP1 强调色 / P2 紫 · 允许超出 0–1 做回弹")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .lineSpacing(3)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.side)
    }

    // MARK: - 输出

    private var codeRows: [(String, String)] {
        let v = fmt(bz)
        return [
            ("CSS", "transition: all \(Int(duration))ms cubic-bezier(\(v));"),
            ("SwiftUI", ".animation(.timingCurve(\(v), duration: \(String(format: "%.2f", duration / 1000))))"),
            ("Core Animation", "CAMediaTimingFunction(controlPoints: \(v))"),
            ("Flutter", "Cubic(\(v))"),
        ]
    }

    private var status: StatusLine {
        let overshoot = bz[1] > 1 || bz[3] > 1 || bz[1] < 0 || bz[3] < 0
        return overshoot
            ? StatusLine(level: .warning,
                         text: "曲线超出 0–1，会产生回弹（CSS / SwiftUI 支持，UIKit 不支持）",
                         trailing: "cubic-bézier", trailingKey: "⌄")
            : StatusLine(level: .ok, text: "曲线有效 · 4 种代码输出",
                         trailing: "cubic-bézier", trailingKey: "⌄")
    }

    // MARK: - 几何与求值

    private var inner: CGFloat { Self.side - Self.pad * 2 }

    private func toPixel(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: Self.pad + CGFloat(x) * inner,
                y: Self.side - Self.pad - CGFloat(y) * inner)
    }

    private func toNormalized(_ p: CGPoint) -> (x: Double, y: Double) {
        (Double((p.x - Self.pad) / inner), Double((Self.side - Self.pad - p.y) / inner))
    }

    private func hitTest(_ p: CGPoint) -> Int? {
        for i in [0, 2] {
            let c = toPixel(bz[i], bz[i + 1])
            if pow(p.x - c.x, 2) + pow(p.y - c.y, 2) < 210 { return i }
        }
        return nil
    }

    /// 三次贝塞尔求值：先由 x 用牛顿迭代反解 t，再取 y —— 与 CSS 实现一致
    private func bezierY(_ x: Double) -> Double {
        let (x1, y1, x2, y2) = (bz[0], bz[1], bz[2], bz[3])
        let cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx
        let cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by
        func fx(_ t: Double) -> Double { ((ax * t + bx) * t + cx) * t }
        func dfx(_ t: Double) -> Double { (3 * ax * t + 2 * bx) * t + cx }

        var t = x
        for _ in 0..<8 {
            let err = fx(t) - x
            let d = dfx(t)
            if abs(err) < 1e-6 || abs(d) < 1e-6 { break }
            t -= err / d
        }
        return ((ay * t + by) * t + cy) * t
    }

    private func ballProgress(_ date: Date) -> Double {
        let cycle = duration / 1000 + 0.56
        let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
        let p = elapsed / (duration / 1000)
        let y = p <= 1 ? bezierY(p) : bezierY(1)
        return min(1, max(0, y))
    }

    private func fmt(_ v: [Double]) -> String {
        v.map { String(format: "%g", ($0 * 100).rounded() / 100) }.joined(separator: ", ")
    }
}
