import SwiftUI
import AppKit

/// 模板 ③ .form 的样板工具
struct ColorTool: ToolView {
    static let meta = ToolMeta(
        id: "color",
        name: "颜色转换",
        category: .style,
        layout: .form,
        symbol: "eyedropper",
        aliases: ["color", "hex", "rgb", "ysh", "yanse"]
    )

    /// Tailwind v3 常用色的示意子集，用于「最接近」提示
    private static let tailwind: [(String, UInt32)] = [
        ("blue-500", 0x3B82F6), ("blue-600", 0x2563EB), ("sky-500", 0x0EA5E9),
        ("cyan-500", 0x06B6D4), ("indigo-500", 0x6366F1), ("violet-500", 0x8B5CF6),
        ("teal-500", 0x14B8A6), ("emerald-500", 0x10B981), ("green-500", 0x22C55E),
        ("amber-500", 0xF59E0B), ("orange-500", 0xF97316), ("red-500", 0xEF4444),
        ("pink-500", 0xEC4899), ("slate-500", 0x64748B), ("gray-500", 0x6B7280),
    ]

    enum Space: Hashable { case sRGB, displayP3 }

    @State private var hexText = "#4A90D9"
    @State private var space: Space = .sRGB
    @State private var includeAlpha = true

    init() {}

    var body: some View {
        StackLayout(status: status) {
            OptionLabel(text: "色彩空间")
            BentoSegments(options: [(Space.sRGB, "sRGB"), (Space.displayP3, "Display P3")],
                          selection: $space)
            Spacer()
            BentoCheck(label: "含 alpha", isOn: $includeAlpha)
        } content: {
            // 输入卡
            Card {
                HStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(swatchColor)
                        .frame(width: 64, height: 64)
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.16), radius: 4, y: 2)

                    VStack(alignment: .leading, spacing: 9) {
                        TextField("", text: $hexText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, design: .monospaced))
                            .padding(.horizontal, 10)
                            .frame(width: 146, height: 31)
                            .sunkenSurface(radius: 8)

                        HStack(spacing: 6) {
                            Button {
                                pickFromScreen()
                            } label: {
                                HStack(spacing: 5) { Text("屏幕取色"); Keycap(text: "⌥⌘P") }
                            }
                            .bentoButton(prominent: true)

                            Button("系统面板") { NSColorPanel.shared.orderFront(nil) }
                                .bentoButton()
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        Text("最接近 Tailwind")
                            .font(.system(size: 11)).foregroundStyle(.tertiary)
                        Text(nearestTailwind)
                            .font(.system(size: 13.5, design: .monospaced))
                    }
                }
                .padding(Tokens.padCard)
            }
            .fixedSize(horizontal: false, vertical: true)

            // 输出卡
            Card(title: "输出格式", dot: ToolCategory.style.tint, meta: "7 种 · 逐行复制") {
                ResultRows(rows: outputRows)
                    .frame(maxHeight: .infinity)
                contrastBar
            }
        }
    }

    // MARK: - 对比度栏

    private var contrastBar: some View {
        HStack(spacing: 20) {
            if let c = parsed {
                let onWhite = Self.contrast(c, NSColor.white)
                let onBlack = Self.contrast(c, NSColor.black)
                contrastItem("对白底", onWhite)
                contrastItem("对黑底", onBlack)
                Text("相对亮度 \(String(format: "%.3f", Self.luminance(c)))")
                    .font(.system(size: 12)).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, Tokens.padCard)
        .frame(height: 44)
        .overlay(alignment: .top) {
            Rectangle().fill(Tokens.separator).frame(height: 0.5)
        }
    }

    private func contrastItem(_ label: String, _ ratio: Double) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 12))
            Text(String(format: "%.2f:1", ratio))
                .font(.system(size: 12, weight: .semibold)).monospacedDigit()
            badge(ratio)
        }
    }

    private func badge(_ r: Double) -> some View {
        let (text, color): (String, Color) =
            r >= 7   ? ("AAA", Tokens.ok) :
            r >= 4.5 ? ("AA", Tokens.ok) :
            r >= 3   ? ("AA 大字", Tokens.warning) : ("不合规", Tokens.error)
        return Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: .rect(cornerRadius: 5))
    }

    // MARK: - 计算

    private var parsed: NSColor? { Self.parse(hexText, p3: space == .displayP3) }

    private var swatchColor: Color {
        parsed.map { Color(nsColor: $0) } ?? Color.gray.opacity(0.3)
    }

    private var outputRows: [(String, String)] {
        guard let c = parsed else { return [] }
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        let a = c.alphaComponent
        let hsl = Self.toHSL(c)
        let hex = String(format: "#%02X%02X%02X", r, g, b)
        let f = { (v: CGFloat) in String(format: "%.2f", v) }
        let alphaHex = String(format: "%02X", Int((a * 255).rounded()))

        return [
            ("HEX", includeAlpha && a < 1 ? hex + alphaHex : hex),
            ("RGB", a < 1 && includeAlpha
                ? "rgba(\(r), \(g), \(b), \(f(a)))" : "rgb(\(r), \(g), \(b))"),
            ("HSL", "hsl(\(hsl.h), \(hsl.s)%, \(hsl.l)%)"),
            ("SwiftUI", space == .displayP3
                ? "Color(.displayP3, red: \(f(c.redComponent)), green: \(f(c.greenComponent)), blue: \(f(c.blueComponent)))"
                : "Color(red: \(f(c.redComponent)), green: \(f(c.greenComponent)), blue: \(f(c.blueComponent)))"),
            ("AppKit", space == .displayP3
                ? "NSColor(displayP3Red: \(f(c.redComponent)), green: \(f(c.greenComponent)), blue: \(f(c.blueComponent)), alpha: \(f(a)))"
                : "NSColor(srgbRed: \(f(c.redComponent)), green: \(f(c.greenComponent)), blue: \(f(c.blueComponent)), alpha: \(f(a)))"),
            ("Flutter", "Color(0x\(alphaHex)\(hex.dropFirst()))"),
            ("CSS var", "--brand: \(hex.lowercased());"),
        ]
    }

    private var nearestTailwind: String {
        guard let c = parsed else { return "—" }
        let r = c.redComponent * 255, g = c.greenComponent * 255, b = c.blueComponent * 255
        var best = ("—", Double.greatestFiniteMagnitude)
        for (name, hex) in Self.tailwind {
            let tr = Double((hex >> 16) & 0xFF), tg = Double((hex >> 8) & 0xFF), tb = Double(hex & 0xFF)
            let d = pow(tr - r, 2) + pow(tg - g, 2) + pow(tb - b, 2)
            if d < best.1 { best = (name, d) }
        }
        return "\(best.0)  Δ\(Int(best.1.squareRoot()))"
    }

    private var status: StatusLine {
        parsed == nil
            ? StatusLine(level: .error, text: "无法解析（支持 #RGB / #RRGGBB / #RRGGBBAA）",
                         trailing: "WCAG 2.1", trailingKey: "⌄")
            : StatusLine(level: .ok, text: "已解析 · 7 种格式",
                         trailing: "WCAG 2.1", trailingKey: "⌄")
    }

    // MARK: - 取色（NSColorSampler：系统级吸管，十行代码）

    private func pickFromScreen() {
        NSColorSampler().show { picked in
            guard let picked else { return }
            let c = picked.usingColorSpace(.sRGB) ?? picked
            hexText = String(format: "#%02X%02X%02X",
                             Int((c.redComponent * 255).rounded()),
                             Int((c.greenComponent * 255).rounded()),
                             Int((c.blueComponent * 255).rounded()))
        }
    }

    // MARK: - 色彩换算

    private static func parse(_ raw: String, p3: Bool) -> NSColor? {
        var s = raw.trimmingCharacters(in: .whitespaces).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8,
              let v = UInt32(s.prefix(6), radix: 16) else { return nil }
        var alpha: CGFloat = 1
        if s.count == 8, let a = UInt32(s.suffix(2), radix: 16) {
            alpha = CGFloat(a) / 255
        }
        let r = CGFloat((v >> 16) & 0xFF) / 255
        let g = CGFloat((v >> 8) & 0xFF) / 255
        let b = CGFloat(v & 0xFF) / 255
        return p3
            ? NSColor(displayP3Red: r, green: g, blue: b, alpha: alpha)
            : NSColor(srgbRed: r, green: g, blue: b, alpha: alpha)
    }

    private static func toHSL(_ c: NSColor) -> (h: Int, s: Int, l: Int) {
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
        let mx = max(r, g, b), mn = min(r, g, b)
        let l = (mx + mn) / 2
        let d = mx - mn
        var h: CGFloat = 0, s: CGFloat = 0
        if d != 0 {
            s = d / (1 - abs(2 * l - 1))
            if mx == r { h = 60 * (((g - b) / d).truncatingRemainder(dividingBy: 6)) }
            else if mx == g { h = 60 * ((b - r) / d + 2) }
            else { h = 60 * ((r - g) / d + 4) }
        }
        return (Int((h < 0 ? h + 360 : h).rounded()), Int((s * 100).rounded()), Int((l * 100).rounded()))
    }

    private static func luminance(_ c: NSColor) -> Double {
        let srgb = c.usingColorSpace(.sRGB) ?? c
        func f(_ v: CGFloat) -> Double {
            let x = Double(v)
            return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * f(srgb.redComponent) + 0.7152 * f(srgb.greenComponent) + 0.0722 * f(srgb.blueComponent)
    }

    private static func contrast(_ a: NSColor, _ b: NSColor) -> Double {
        let l1 = luminance(a), l2 = luminance(b)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }
}
