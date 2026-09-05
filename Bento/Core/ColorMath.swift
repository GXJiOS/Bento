import Foundation

/// 色彩数学。纯 Double 运算，不依赖 AppKit —— 可以脱离 App 直接验证。
/// 色彩空间相关（Display P3、屏幕取色）留在 View 层交给 NSColor。
enum ColorMath {

    // MARK: - 模型

    struct RGB: Equatable {
        var r: Double, g: Double, b: Double, a: Double = 1   // 0...1

        var hex: String {
            String(format: "#%02X%02X%02X",
                   Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
        }
        var hexA: String {
            hex + String(format: "%02X", Int((a * 255).rounded()))
        }
        var bytes: (Int, Int, Int) {
            (Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
        }
    }

    struct HSL: Equatable {
        var h: Double, s: Double, l: Double, a: Double = 1   // h: 0...360, s/l: 0...1
    }

    // MARK: - 解析与转换

    static func parse(_ raw: String) -> RGB? {
        var s = raw.trimmingCharacters(in: .whitespaces).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        if s.count == 4 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let v = UInt32(s.prefix(6), radix: 16) else { return nil }
        var alpha = 1.0
        if s.count == 8, let a = UInt32(s.suffix(2), radix: 16) { alpha = Double(a) / 255 }
        return RGB(r: Double((v >> 16) & 0xFF) / 255,
                   g: Double((v >> 8) & 0xFF) / 255,
                   b: Double(v & 0xFF) / 255,
                   a: alpha)
    }

    static func toHSL(_ c: RGB) -> HSL {
        let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b)
        let l = (mx + mn) / 2, d = mx - mn
        guard d != 0 else { return HSL(h: 0, s: 0, l: l, a: c.a) }
        let s = d / (1 - abs(2 * l - 1))
        var h: Double
        if mx == c.r { h = 60 * (((c.g - c.b) / d).truncatingRemainder(dividingBy: 6)) }
        else if mx == c.g { h = 60 * ((c.b - c.r) / d + 2) }
        else { h = 60 * ((c.r - c.g) / d + 4) }
        return HSL(h: h < 0 ? h + 360 : h, s: s, l: l, a: c.a)
    }

    static func toRGB(_ hsl: HSL) -> RGB {
        let c = (1 - abs(2 * hsl.l - 1)) * hsl.s
        let hp = hsl.h.truncatingRemainder(dividingBy: 360) / 60
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let m = hsl.l - c / 2
        let (r, g, b): (Double, Double, Double)
        switch hp {
        case 0..<1: (r, g, b) = (c, x, 0)
        case 1..<2: (r, g, b) = (x, c, 0)
        case 2..<3: (r, g, b) = (0, c, x)
        case 3..<4: (r, g, b) = (0, x, c)
        case 4..<5: (r, g, b) = (x, 0, c)
        default:    (r, g, b) = (c, 0, x)
        }
        return RGB(r: clamp(r + m), g: clamp(g + m), b: clamp(b + m), a: hsl.a)
    }

    static func clamp(_ v: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double {
        min(hi, max(lo, v))
    }

    // MARK: - WCAG

    /// 相对亮度（WCAG 2.1 定义，sRGB 线性化后加权）
    static func luminance(_ c: RGB) -> Double {
        func f(_ v: Double) -> Double {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b)
    }

    static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let l1 = luminance(a), l2 = luminance(b)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    enum WCAGLevel: String {
        case aaa = "AAA", aa = "AA", aaLarge = "AA 大字", fail = "不合规"

        var passes: Bool { self != .fail }
    }

    static func level(_ ratio: Double, largeText: Bool = false) -> WCAGLevel {
        if largeText {
            if ratio >= 4.5 { return .aaa }
            if ratio >= 3 { return .aa }
            return .fail
        }
        if ratio >= 7 { return .aaa }
        if ratio >= 4.5 { return .aa }
        if ratio >= 3 { return .aaLarge }
        return .fail
    }

    /// 保持色相与饱和度，只推明度，找到刚好达标的最近颜色。
    /// 两个方向都试，取改动更小的那个；都不行返回 nil（比如背景是中灰时）。
    static func adjust(_ fg: RGB, on bg: RGB, target: Double) -> RGB? {
        guard contrast(fg, bg) < target else { return fg }
        let hsl = toHSL(fg)

        func at(_ l: Double) -> RGB { toRGB(HSL(h: hsl.h, s: hsl.s, l: l, a: hsl.a)) }

        /// 往某个端点（0 = 全黑 / 1 = 全白）方向二分。
        /// 不变量：lo 侧始终不达标、hi 侧始终达标，收敛后 hi 就是最接近原色的达标点。
        func search(towards endpoint: Double) -> RGB? {
            guard contrast(at(endpoint), bg) >= target else { return nil }  // 走到头都不达标
            var lo = hsl.l, hi = endpoint
            for _ in 0..<30 {
                let mid = (lo + hi) / 2
                if contrast(at(mid), bg) >= target { hi = mid } else { lo = mid }
                if abs(hi - lo) < 0.0005 { break }
            }
            return at(hi)
        }

        let candidates = [search(towards: 0), search(towards: 1)].compactMap { $0 }
        // 两个方向都可行时，取明度改动更小的那个
        return candidates.min { abs(toHSL($0).l - hsl.l) < abs(toHSL($1).l - hsl.l) }
    }

    // MARK: - 调色板

    enum PaletteStyle: String, CaseIterable {
        case tailwind, material

        var label: String { self == .tailwind ? "Tailwind 风格" : "Material 风格" }

        var stops: [(name: String, lightness: Double)] {
            switch self {
            case .tailwind:
                return [("50", 0.97), ("100", 0.94), ("200", 0.86), ("300", 0.77),
                        ("400", 0.66), ("500", 0.55), ("600", 0.47), ("700", 0.39),
                        ("800", 0.31), ("900", 0.24), ("950", 0.15)]
            case .material:
                return [("50", 0.95), ("100", 0.88), ("200", 0.79), ("300", 0.69),
                        ("400", 0.60), ("500", 0.50), ("600", 0.44), ("700", 0.37),
                        ("800", 0.30), ("900", 0.21)]
            }
        }
    }

    /// 以输入色作为 500 档的锚点，按明度曲线铺开其余档位。
    /// 两端会降饱和 —— 真实色卡里最浅和最深的档都不会是满饱和，否则看起来发脏。
    static func palette(_ base: RGB, style: PaletteStyle) -> [(name: String, color: RGB)] {
        let hsl = toHSL(base)
        let anchor = style.stops.first { $0.name == "500" }?.lightness ?? 0.55
        let shift = hsl.l - anchor          // 输入色偏离标准 500 多少，整体跟着挪

        return style.stops.map { stop in
            let l = clamp(stop.lightness + shift * 0.35, 0.04, 0.98)
            // 距离中间档越远，饱和度衰减越多
            let distance = abs(l - 0.55) / 0.55
            let s = clamp(hsl.s * (1 - distance * distance * 0.35), 0, 1)
            return (stop.name, toRGB(HSL(h: hsl.h, s: s, l: l, a: 1)))
        }
    }

    // MARK: - 混色与配色

    static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        RGB(r: a.r + (b.r - a.r) * t,
            g: a.g + (b.g - a.g) * t,
            b: a.b + (b.b - a.b) * t,
            a: a.a + (b.a - a.a) * t)
    }

    /// 色相环上的经典配色关系
    static func harmony(_ base: RGB) -> [(name: String, colors: [RGB])] {
        let h = toHSL(base)
        func rotate(_ deg: Double) -> RGB {
            toRGB(HSL(h: (h.h + deg).truncatingRemainder(dividingBy: 360), s: h.s, l: h.l, a: 1))
        }
        return [
            ("互补", [base, rotate(180)]),
            ("三分", [base, rotate(120), rotate(240)]),
            ("邻近", [rotate(-30), base, rotate(30)]),
            ("分裂互补", [base, rotate(150), rotate(210)]),
        ]
    }

    // MARK: - Tailwind 最近色

    /// Tailwind v3 常用色的示意子集
    static let tailwindPalette: [(String, UInt32)] = [
        ("slate-500", 0x64748B), ("gray-500", 0x6B7280), ("red-500", 0xEF4444),
        ("orange-500", 0xF97316), ("amber-500", 0xF59E0B), ("yellow-500", 0xEAB308),
        ("lime-500", 0x84CC16), ("green-500", 0x22C55E), ("emerald-500", 0x10B981),
        ("teal-500", 0x14B8A6), ("cyan-500", 0x06B6D4), ("sky-500", 0x0EA5E9),
        ("blue-500", 0x3B82F6), ("indigo-500", 0x6366F1), ("violet-500", 0x8B5CF6),
        ("purple-500", 0xA855F7), ("fuchsia-500", 0xD946EF), ("pink-500", 0xEC4899),
        ("rose-500", 0xF43F5E),
    ]

    static func nearestTailwind(_ c: RGB) -> (name: String, distance: Int) {
        let (r, g, b) = c.bytes
        var best = ("—", Double.greatestFiniteMagnitude)
        for (name, hex) in tailwindPalette {
            let tr = Double((hex >> 16) & 0xFF), tg = Double((hex >> 8) & 0xFF), tb = Double(hex & 0xFF)
            // 加权欧氏距离，权重贴近人眼对绿色更敏感的事实
            let d = 2 * pow(tr - Double(r), 2) + 4 * pow(tg - Double(g), 2) + 3 * pow(tb - Double(b), 2)
            if d < best.1 { best = (name, d) }
        }
        return (best.0, Int((best.1 / 9).squareRoot()))
    }
}
