import SwiftUI

/// 模板 ② .stacked 的样板工具
struct RegexTool: ToolView {
    static let meta = ToolMeta(
        id: "regex",
        name: "正则测试器",
        category: .formatting,
        layout: .stacked,
        symbol: "magnifyingglass",
        aliases: ["regex", "re", "zz", "zhengze"]
    )

    private static let presets: [(String, String)] = [
        ("日期", #"(\d{4})-(\d{2})-(\d{2})"#),
        ("手机号", #"1[3-9]\d{9}"#),
        ("邮箱", #"[\w.+-]+@[\w-]+\.[\w.]+"#),
        ("URL", #"https?://[^\s]+"#),
    ]

    @State private var pattern = #"(\d{4})-(\d{2})-(\d{2})"#
    @State private var sample = """
        订单 2026-08-01 创建，2026-08-15 到期
        发票 2026-07-20 已开，退款截止 2026-09-01
        """
    @State private var caseInsensitive = false
    @State private var dotMatchesLines = false

    init() {}

    var body: some View {
        StackLayout(status: status) {
            OptionLabel(text: "常用模式")
            ForEach(Self.presets, id: \.0) { name, p in
                Button(name) { pattern = p }.bentoButton()
            }
            Spacer()
            BentoCheck(label: "忽略大小写", isOn: $caseInsensitive)
            BentoCheck(label: ". 匹配换行", isOn: $dotMatchesLines)
        } content: {
            // 表达式
            Card {
                HStack(spacing: 9) {
                    Text("/").font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    TextField("", text: $pattern)
                        .textFieldStyle(.plain)
                        .font(Tokens.mono)
                        .padding(.horizontal, 10)
                        .frame(height: 31)
                        .sunkenSurface(radius: 8)
                    Text("/").font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Text(flagString)
                        .font(Tokens.mono)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 22)
                }
                .padding(.horizontal, Tokens.padCard)
                .frame(height: 50)
            }
            .fixedSize(horizontal: false, vertical: true)

            // 测试文本 + 高亮预览（同卡两段，避免卡片过碎）
            Card(title: "测试文本", dot: ToolCategory.formatting.tint, meta: sampleMeta) {
                CodeArea(text: $sample)
                    .frame(height: 96)
                HStack {
                    Text("高亮预览").font(Tokens.sectionHead).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, Tokens.padCard)
                .frame(height: Tokens.cardHeadH)
                .overlay(alignment: .top) {
                    Rectangle().fill(Tokens.separator).frame(height: 0.5)
                }
                CodeArea(text: .constant(sample), isEditable: false, highlights: matchRanges)
            }

            // 捕获分组
            Card(title: "捕获分组", dot: ToolCategory.image.tint, meta: groupMeta) {
                groupTable
            }
            .frame(height: 176)
        }
    }

    // MARK: - 分组表

    private var groupTable: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                HStack(spacing: 0) {
                    cell("#", width: 38, header: true)
                    cell("匹配", width: 150, header: true)
                    cell("位置", width: 60, header: true)
                    ForEach(0..<groupCount, id: \.self) { i in
                        cell("$\(i + 1)", width: 78, header: true)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 28)
                .background(Tokens.cardBG)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Tokens.separator).frame(height: 0.5)
                }

                if matches.isEmpty {
                    HStack {
                        Text(patternError == nil ? "无匹配" : "—")
                            .font(Tokens.mono).foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.horizontal, Tokens.padCard)
                    .frame(height: 30)
                } else {
                    ForEach(Array(matches.enumerated()), id: \.offset) { idx, m in
                        HStack(spacing: 0) {
                            cell("\(idx + 1)", width: 38, dim: true)
                            cell(text(in: m.range), width: 150)
                            cell("\(m.range.location)", width: 60, dim: true)
                            ForEach(0..<groupCount, id: \.self) { g in
                                let r = m.range(at: g + 1)
                                cell(r.location == NSNotFound ? "—" : text(in: r), width: 78)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(height: 30)
                        .overlay(alignment: .top) {
                            Rectangle().fill(Tokens.separator).frame(height: 0.5)
                        }
                    }
                }
            }
        }
        .scrollIndicators(.never)
    }

    private func cell(_ s: String, width: CGFloat, header: Bool = false, dim: Bool = false) -> some View {
        Text(s)
            .font(header ? .system(size: 11, weight: .semibold) : Tokens.mono)
            .foregroundStyle(header || dim ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
            .padding(.leading, Tokens.padCard)
    }

    // MARK: - 匹配

    private var flagString: String {
        var f = "g"
        if caseInsensitive { f += "i" }
        if dotMatchesLines { f += "s" }
        return f
    }

    private var regex: NSRegularExpression? {
        var opts: NSRegularExpression.Options = []
        if caseInsensitive { opts.insert(.caseInsensitive) }
        if dotMatchesLines { opts.insert(.dotMatchesLineSeparators) }
        return try? NSRegularExpression(pattern: pattern, options: opts)
    }

    private var patternError: String? {
        var opts: NSRegularExpression.Options = []
        if caseInsensitive { opts.insert(.caseInsensitive) }
        if dotMatchesLines { opts.insert(.dotMatchesLineSeparators) }
        do {
            _ = try NSRegularExpression(pattern: pattern, options: opts)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private var matches: [NSTextCheckingResult] {
        guard let regex else { return [] }
        let ns = sample as NSString
        return regex.matches(in: sample, range: NSRange(location: 0, length: ns.length))
    }

    private var matchRanges: [NSRange] { matches.map(\.range) }

    private var groupCount: Int { regex?.numberOfCaptureGroups ?? 0 }

    private func text(in range: NSRange) -> String {
        guard range.location != NSNotFound,
              NSMaxRange(range) <= (sample as NSString).length else { return "—" }
        return (sample as NSString).substring(with: range)
    }

    private var sampleMeta: String {
        "\(sample.components(separatedBy: .newlines).count) 行 · \(sample.count) 字符"
    }

    private var groupMeta: String {
        matches.isEmpty ? "—" : "\(matches.count) 处 · \(groupCount) 组"
    }

    private var status: StatusLine {
        if let err = patternError {
            return StatusLine(level: .error, text: "表达式无效：\(err)",
                              trailing: "ICU Regex", trailingKey: "⌄")
        }
        if matches.isEmpty {
            return StatusLine(level: .warning, text: "表达式有效，但无匹配",
                              trailing: "ICU Regex", trailingKey: "⌄")
        }
        return StatusLine(level: .ok,
                          text: "匹配 \(matches.count) 处 · \(groupCount) 个捕获分组",
                          trailing: "ICU Regex", trailingKey: "⌄")
    }
}
