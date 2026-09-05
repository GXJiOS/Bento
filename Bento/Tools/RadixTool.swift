import SwiftUI

struct RadixTool: ToolView {
    static let meta = ToolMeta(
        id: "radix", name: "进制转换", category: .encoding, layout: .form,
        symbol: "number",
        aliases: ["radix", "hex", "bin", "oct", "jz", "jinzhi"]
    )

    enum Base: Int, Hashable, CaseIterable {
        case auto = 0, bin = 2, oct = 8, dec = 10, hex = 16

        var label: String {
            switch self {
            case .auto: return "自动"
            case .bin:  return "2"
            case .oct:  return "8"
            case .dec:  return "10"
            case .hex:  return "16"
            }
        }
    }

    @State private var input = "1735689600"
    @State private var base: Base = .auto
    @State private var groupDigits = true
    @State private var bitWidth = 64

    init() {}

    var body: some View {
        StackLayout(status: status) {
            OptionLabel(text: "输入进制")
            BentoSegments(options: Base.allCases.map { ($0, $0.label) }, selection: $base)
            BentoCheck(label: "分组显示", isOn: $groupDigits)
            Spacer()
            OptionLabel(text: "位宽")
            BentoSegments(options: [(32, "32"), (64, "64")], selection: $bitWidth)
        } content: {
            Card {
                HStack(spacing: 14) {
                    TextField("", text: $input)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, design: .monospaced))
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .sunkenSurface(radius: 8)
                    Text(detectedLabel)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(width: 150, alignment: .leading)
                }
                .padding(Tokens.padCard)
            }
            .fixedSize(horizontal: false, vertical: true)

            Card(title: "输出格式", dot: ToolCategory.encoding.tint, meta: "6 种 · 逐行复制") {
                ResultRows(rows: rows, keyWidth: 118)
                    .frame(maxHeight: .infinity)
                bitGrid
            }
        }
    }

    // MARK: - 位图

    /// 点一下翻转某一位 —— 调寄存器 / flag 的时候比心算快
    private var bitGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let v = value {
                let bits = (0..<bitWidth).reversed().map { (v >> UInt64($0)) & 1 }
                HStack(spacing: 3) {
                    ForEach(Array(bits.enumerated()), id: \.offset) { index, bit in
                        let pos = bitWidth - 1 - index
                        Text("\(bit)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(bit == 1 ? AnyShapeStyle(Color.white)
                                                      : AnyShapeStyle(.tertiary))
                            .frame(width: 13, height: 17)
                            .background(bit == 1 ? AnyShapeStyle(Tokens.accentGradient)
                                                 : AnyShapeStyle(Tokens.sunkenBG),
                                        in: .rect(cornerRadius: 3))
                            .onTapGesture { toggleBit(pos) }
                            .help("bit \(pos)")
                        if pos % 8 == 0 && pos != 0 {
                            Spacer().frame(width: 5)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Tokens.padCard)
        .frame(height: 46)
        .overlay(alignment: .top) {
            Rectangle().fill(Tokens.separator).frame(height: 0.5)
        }
    }

    // MARK: - 解析

    private var detected: Base {
        if base != .auto { return base }
        let t = input.trimmingCharacters(in: .whitespaces).lowercased()
        if t.hasPrefix("0x") { return .hex }
        if t.hasPrefix("0b") { return .bin }
        if t.hasPrefix("0o") { return .oct }
        if t.contains(where: { "abcdef".contains($0) }) { return .hex }
        if !t.isEmpty, t.allSatisfy({ $0 == "0" || $0 == "1" }), t.count > 3 { return .bin }
        return .dec
    }

    private var detectedLabel: String {
        guard value != nil else { return input.isEmpty ? "" : "无法解析" }
        return base == .auto ? "自动识别为 \(detected.rawValue) 进制" : "按 \(detected.rawValue) 进制解析"
    }

    private var value: UInt64? {
        var t = input.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
        guard !t.isEmpty else { return nil }
        for prefix in ["0x", "0b", "0o"] where t.hasPrefix(prefix) { t = String(t.dropFirst(2)) }
        guard let v = UInt64(t, radix: detected.rawValue) else { return nil }
        if bitWidth == 32 && v > UInt64(UInt32.max) { return nil }
        return v
    }

    private var rows: [(String, String)] {
        guard let v = value else { return [] }
        let bin = String(v, radix: 2)
        let hex = String(v, radix: 16).uppercased()
        let padded = String(repeating: "0", count: max(0, bitWidth - bin.count)) + bin

        return [
            ("十进制", groupDigits ? Self.groupDecimal(v) : "\(v)"),
            ("十六进制", "0x" + (groupDigits ? hex.grouped(4, from: .right) : hex)),
            ("八进制", "0o" + String(v, radix: 8)),
            ("二进制", "0b" + (groupDigits ? padded.grouped(8, from: .right) : bin)),
            ("字节数", "\(max(1, (bin.count + 7) / 8)) 字节 · 有效位 \(bin.count)"),
            ("有符号解读", signedLabel(v)),
        ]
    }

    private func signedLabel(_ v: UInt64) -> String {
        if bitWidth == 32 {
            let s = Int32(bitPattern: UInt32(truncatingIfNeeded: v))
            return "int32 \(s)   ·   uint32 \(UInt32(truncatingIfNeeded: v))"
        }
        return "int64 \(Int64(bitPattern: v))   ·   uint64 \(v)"
    }

    private func toggleBit(_ pos: Int) {
        guard let v = value else { return }
        let flipped = v ^ (UInt64(1) << UInt64(pos))
        // 保持用户当前的输入进制，避免一点位就跳回十进制
        switch detected {
        case .hex: input = "0x" + String(flipped, radix: 16).uppercased()
        case .bin: input = "0b" + String(flipped, radix: 2)
        case .oct: input = "0o" + String(flipped, radix: 8)
        default:   input = "\(flipped)"
        }
    }

    private var status: StatusLine {
        if input.trimmingCharacters(in: .whitespaces).isEmpty {
            return StatusLine(level: .idle, text: "等待输入", trailing: "\(bitWidth) 位", trailingKey: "⌄")
        }
        guard value != nil else {
            let hint = bitWidth == 32 ? "无法解析 · 或超出 32 位范围" : "无法按 \(detected.rawValue) 进制解析"
            return StatusLine(level: .error, text: hint, trailing: "\(bitWidth) 位", trailingKey: "⌄")
        }
        return StatusLine(level: .ok, text: "已解析 · 点位图可翻转某一位",
                          trailing: "\(bitWidth) 位", trailingKey: "⌄")
    }

    private static func groupDecimal(_ v: UInt64) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }
}

private extension String {
    enum GroupSide { case left, right }

    /// 每 n 位插一个空格；十六进制/二进制从右往左分组才对齐字节边界
    func grouped(_ n: Int, from side: GroupSide) -> String {
        guard count > n else { return self }
        if side == .left { return chunked(n).joined(separator: " ") }
        let rem = count % n
        var parts: [String] = []
        var idx = startIndex
        if rem > 0 {
            let end = index(startIndex, offsetBy: rem)
            parts.append(String(self[idx..<end]))
            idx = end
        }
        while idx < endIndex {
            let end = index(idx, offsetBy: n)
            parts.append(String(self[idx..<end]))
            idx = end
        }
        return parts.joined(separator: " ")
    }
}
