import Foundation

/// CSS 声明 → SwiftUI 修饰符。
///
/// 不做完整 CSS 解析（选择器、级联、媒体查询都不管），只处理
/// 「从浏览器 devtools 里 copy 一段 computed style 过来」这个真实场景。
/// 认不出的属性会原样列出来，而不是悄悄丢掉。
enum CSSConverter {

    struct Declaration: Equatable {
        let property: String
        let value: String
    }

    struct Result {
        var modifiers: [String] = []
        var unsupported: [Declaration] = []
        var notes: [String] = []
    }

    // MARK: - 解析

    static func parse(_ css: String) -> [Declaration] {
        var body = css.trimmingCharacters(in: .whitespacesAndNewlines)
        // 允许直接粘 `.foo { ... }`
        if let open = body.firstIndex(of: "{"), let close = body.lastIndex(of: "}") {
            body = String(body[body.index(after: open)..<close])
        }
        return body.components(separatedBy: ";").compactMap { line in
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, !t.hasPrefix("//"), !t.hasPrefix("/*"),
                  let colon = t.firstIndex(of: ":") else { return nil }
            return Declaration(
                property: String(t[t.startIndex..<colon])
                    .trimmingCharacters(in: .whitespaces).lowercased(),
                value: String(t[t.index(after: colon)...])
                    .trimmingCharacters(in: .whitespaces)
            )
        }
    }

    // MARK: - 转换

    static func toSwiftUI(_ decls: [Declaration]) -> Result {
        var r = Result()
        // SwiftUI 里修饰符顺序影响渲染结果（典型的是 .background 必须在 .padding 之后，
        // 否则背景不覆盖内边距），所以分类收集，最后按固定顺序拼装，
        // 而不是按 CSS 声明出现的顺序。
        var textMods: [String] = []      // 字体 / 颜色 / 行距
        var layoutMods: [String] = []    // frame
        var decorMods: [String] = []     // background / border / clip
        var effectMods: [String] = []    // shadow / opacity

        var fontSize: Double?
        var fontWeight: String?
        var fontFamily: String?
        var padding: (t: Double, r: Double, b: Double, l: Double)?
        var borderRadius: Double?
        var borderWidth: Double?
        var borderColor: String?
        var width: Double?, height: Double?
        var isFlex = false, flexColumn = false, gap: Double?
        var background: String?
        var lineHeight: String?
        var letterSpacing: String?
        var overflowHidden = false

        for d in decls {
            switch d.property {
            case "color":
                if let c = colorLiteral(d.value) { textMods.append(".foregroundStyle(\(c))") }
                else { r.unsupported.append(d) }

            case "background", "background-color":
                if let c = colorLiteral(d.value) { background = ".background(\(c))" }
                else if d.value.contains("gradient") {
                    r.notes.append("渐变背景请用「渐变生成」工具转 LinearGradient")
                    r.unsupported.append(d)
                } else { r.unsupported.append(d) }

            case "font-size":   fontSize = length(d.value)
            case "font-weight": fontWeight = weight(d.value)
            case "font-family":
                fontFamily = d.value.components(separatedBy: ",").first?
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))

            case "font-style":
                if d.value == "italic" { textMods.append(".italic()") }

            case "opacity":
                if let v = Double(d.value) { effectMods.append(".opacity(\(fmt(v)))") }

            case "border-radius":
                borderRadius = length(d.value.components(separatedBy: " ").first ?? d.value)

            case "border", "border-width", "border-color":
                if d.property == "border" {
                    let parts = d.value.components(separatedBy: " ")
                    borderWidth = parts.first.flatMap(length)
                    borderColor = parts.last.flatMap(colorLiteral)
                } else if d.property == "border-width" {
                    borderWidth = length(d.value)
                } else {
                    borderColor = colorLiteral(d.value)
                }

            case "padding":
                padding = box(d.value)
            case "padding-top":    padding = merge(padding, top: length(d.value))
            case "padding-right":  padding = merge(padding, right: length(d.value))
            case "padding-bottom": padding = merge(padding, bottom: length(d.value))
            case "padding-left":   padding = merge(padding, left: length(d.value))

            case "width":     width = length(d.value)
            case "height":    height = length(d.value)
            case "max-width":
                if let v = length(d.value) { layoutMods.append(".frame(maxWidth: \(fmt(v)))") }

            case "text-align":
                switch d.value {
                case "center": textMods.append(".multilineTextAlignment(.center)")
                case "right":  textMods.append(".multilineTextAlignment(.trailing)")
                default:       textMods.append(".multilineTextAlignment(.leading)")
                }

            case "line-height":
                lineHeight = d.value

            case "letter-spacing":
                letterSpacing = d.value

            case "box-shadow":
                effectMods.append(shadow(d.value))

            case "display":
                if d.value == "flex" || d.value == "inline-flex" { isFlex = true }
                else if d.value == "none" { r.notes.append("display:none 对应条件渲染，不是修饰符") }

            case "flex-direction":
                flexColumn = d.value.hasPrefix("column")

            case "gap", "row-gap", "column-gap":
                gap = length(d.value)

            case "overflow", "overflow-x", "overflow-y":
                if d.value == "hidden" { overflowHidden = true }

            case "cursor", "user-select", "box-sizing", "transition", "outline":
                continue   // 这些在 SwiftUI 里没有对应概念，静默跳过

            default:
                r.unsupported.append(d)
            }
        }

        // ── 字体三件套合成一个 .font() ──
        if fontSize != nil || fontWeight != nil || fontFamily != nil {
            let size = fontSize.map { fmt($0) } ?? "13"
            if let family = fontFamily, !["-apple-system", "system-ui", "sans-serif", "inherit"]
                .contains(family.lowercased()) {
                textMods.insert(".font(.custom(\"\(family)\", size: \(size)))", at: 0)
                if let w = fontWeight { textMods.insert(".fontWeight(.\(w))", at: 1) }
            } else {
                let w = fontWeight.map { ", weight: .\($0)" } ?? ""
                textMods.insert(".font(.system(size: \(size)\(w)))", at: 0)
            }
        }

        // ── em 相对的是当前字号，不是根字号，所以要等 font-size 确定后再算 ──
        let fs = fontSize ?? 16
        if let lh = lineHeight {
            if let ratio = Double(lh) {
                textMods.append(".lineSpacing(\(fmt(ratio * fs - fs)))")
                r.notes.append("line-height 是倍数，已换算成 lineSpacing（总行高 − 字号）")
            } else if let v = emAware(lh, fontSize: fs) {
                textMods.append(".lineSpacing(\(fmt(v - fs)))")
            }
        }
        if let ls = letterSpacing, let v = emAware(ls, fontSize: fs) {
            textMods.append(".tracking(\(fmt(v)))")
        }

        if let p = padding {
            if p.t == p.r, p.r == p.b, p.b == p.l {
                layoutMods.append(".padding(\(fmt(p.t)))")
            } else if p.t == p.b, p.l == p.r {
                layoutMods.append(".padding(.vertical, \(fmt(p.t)))")
                layoutMods.append(".padding(.horizontal, \(fmt(p.l)))")
            } else {
                layoutMods.append(".padding(EdgeInsets(top: \(fmt(p.t)), leading: \(fmt(p.l)), bottom: \(fmt(p.b)), trailing: \(fmt(p.r))))")
            }
        }

        if width != nil || height != nil {
            let w = width.map { "width: \(fmt($0))" }
            let h = height.map { "height: \(fmt($0))" }
            layoutMods.append(".frame(\([w, h].compactMap { $0 }.joined(separator: ", ")))")
        }

        // background 必须排在 padding 之后
        if let bg = background { decorMods.append(bg) }

        if let radius = borderRadius {
            if let bw = borderWidth, let bc = borderColor {
                decorMods.append(".overlay(RoundedRectangle(cornerRadius: \(fmt(radius)), style: .continuous).strokeBorder(\(bc), lineWidth: \(fmt(bw))))")
            }
            decorMods.append(".clipShape(.rect(cornerRadius: \(fmt(radius))))")
        } else if let bw = borderWidth, let bc = borderColor {
            decorMods.append(".border(\(bc), width: \(fmt(bw)))")
        } else if overflowHidden {
            decorMods.append(".clipped()")
        }

        if isFlex {
            let stack = flexColumn ? "VStack" : "HStack"
            let spacing = gap.map { "spacing: \(fmt($0))" } ?? ""
            r.notes.insert("display:flex → 用 \(stack)(\(spacing)) { … } 包住子视图，不是修饰符", at: 0)
        }

        // 固定顺序拼装：文本 → 尺寸/内距 → 背景/描边/裁剪 → 阴影/透明
        r.modifiers = textMods + layoutMods + decorMods + effectMods
        return r
    }

    // MARK: - 值解析

    static func length(_ v: String) -> Double? {
        let s = v.trimmingCharacters(in: .whitespaces).lowercased()
        for unit in ["px", "pt", "rem", "em", "%"] where s.hasSuffix(unit) {
            guard let n = Double(s.dropLast(unit.count)) else { return nil }
            // rem/em 按 16px 基准折算，这是浏览器默认值
            return (unit == "rem" || unit == "em") ? n * 16 : n
        }
        return Double(s)
    }

    /// em 相对当前字号，rem 相对根字号（16px）
    static func emAware(_ v: String, fontSize: Double) -> Double? {
        let s = v.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasSuffix("em"), !s.hasSuffix("rem"), let n = Double(s.dropLast(2)) {
            return n * fontSize
        }
        return length(s)
    }

    static func colorLiteral(_ v: String) -> String? {
        let s = v.trimmingCharacters(in: .whitespaces).lowercased()
        if s == "transparent" { return ".clear" }
        if s == "white" { return ".white" }
        if s == "black" { return ".black" }
        if s.hasPrefix("#"), let c = ColorMath.parse(s) {
            return String(format: "Color(.sRGB, red: %.3f, green: %.3f, blue: %.3f, opacity: %.2f)",
                          c.r, c.g, c.b, c.a)
        }
        if s.hasPrefix("rgb") {
            let nums = s.components(separatedBy: CharacterSet(charactersIn: "(),"))
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard nums.count >= 3 else { return nil }
            let a = nums.count >= 4 ? nums[3] : 1
            return String(format: "Color(.sRGB, red: %.3f, green: %.3f, blue: %.3f, opacity: %.2f)",
                          nums[0] / 255, nums[1] / 255, nums[2] / 255, a)
        }
        return nil
    }

    private static func weight(_ v: String) -> String? {
        switch v.trimmingCharacters(in: .whitespaces) {
        case "100": return "ultraLight"
        case "200": return "thin"
        case "300": return "light"
        case "400", "normal": return "regular"
        case "500": return "medium"
        case "600": return "semibold"
        case "700", "bold": return "bold"
        case "800": return "heavy"
        case "900": return "black"
        default: return nil
        }
    }

    private static func box(_ v: String) -> (t: Double, r: Double, b: Double, l: Double)? {
        let parts = v.components(separatedBy: " ").compactMap { length($0) }
        switch parts.count {
        case 1: return (parts[0], parts[0], parts[0], parts[0])
        case 2: return (parts[0], parts[1], parts[0], parts[1])
        case 3: return (parts[0], parts[1], parts[2], parts[1])
        case 4: return (parts[0], parts[1], parts[2], parts[3])
        default: return nil
        }
    }

    private static func merge(_ p: (t: Double, r: Double, b: Double, l: Double)?,
                              top: Double? = nil, right: Double? = nil,
                              bottom: Double? = nil, left: Double? = nil)
        -> (t: Double, r: Double, b: Double, l: Double) {
        var out = p ?? (0, 0, 0, 0)
        if let top { out.t = top }
        if let right { out.r = right }
        if let bottom { out.b = bottom }
        if let left { out.l = left }
        return out
    }

    private static func shadow(_ v: String) -> String {
        let parts = v.components(separatedBy: " ")
        let nums = parts.compactMap { length($0) }
        let color = parts.first { $0.hasPrefix("#") || $0.hasPrefix("rgb") }
            .flatMap { colorLiteral($0) } ?? ".black.opacity(0.2)"
        guard nums.count >= 3 else { return ".shadow(color: \(color), radius: 4)" }
        // SwiftUI 的 radius 约等于 CSS blur 的一半
        return String(format: ".shadow(color: %@, radius: %g, x: %g, y: %g)",
                      color, nums[2] / 2, nums[0], nums[1])
    }

    private static func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%g", v)
    }
}
