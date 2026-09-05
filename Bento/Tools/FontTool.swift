import SwiftUI
import AppKit

struct FontTool: ToolView {
    static let meta = ToolMeta(
        id: "font", name: "字体预览", category: .style, layout: .canvas,
        symbol: "character.book.closed",
        aliases: ["font", "typeface", "preview", "zt", "ziti"]
    )

    @State private var query = ""
    @State private var selected = "SF Pro Text"
    @State private var sampleText = "敏捷的棕色狐狸跳过懒狗 The quick brown fox 0123456789"
    @State private var size: Double = 20
    @State private var monoOnly = false

    /// 系统字体列表只取一次，几百项每次 body 求值都拉一遍会卡
    private static let families: [String] = NSFontManager.shared.availableFontFamilies.sorted()
    private static let monoFamilies: Set<String> = {
        var out = Set<String>()
        for f in families {
            if let font = NSFont(name: f, size: 12), font.isFixedPitch { out.insert(f) }
        }
        return out
    }()

    init() {}

    var body: some View {
        StackLayout(status: status) {
            OptionLabel(text: "字号")
            Slider(value: $size, in: 9...64, step: 1).frame(width: 140)
            Text("\(Int(size))").font(Tokens.mono).monospacedDigit().frame(width: 26)
            BentoCheck(label: "只看等宽", isOn: $monoOnly)
            Spacer()
            CopyButton(value: codeSnippet, compact: false)
        } content: {
            HStack(spacing: Tokens.gapCard) {
                Card(title: "字族", dot: ToolCategory.style.tint,
                     meta: "\(filtered.count) / \(Self.families.count)") {
                    familyList
                }
                .frame(width: 250)

                Card(title: "预览", dot: ToolCategory.image.tint, meta: selected) {
                    previewPane
                }
            }

            Card(title: "代码", dot: ToolCategory.formatting.tint, meta: "3 种 · 逐行复制") {
                ResultRows(rows: codeRows, keyWidth: 96)
            }
            .frame(height: 148)
        }
    }

    // MARK: - 视图

    private var familyList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                TextField("搜索字族", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .sunkenSurface(radius: 7)
            .padding(.horizontal, Tokens.padCard)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(filtered, id: \.self) { family in
                        HStack {
                            Text(family)
                                .font(.custom(family, size: 13))
                                .lineLimit(1)
                            Spacer()
                            if Self.monoFamilies.contains(family) {
                                Text("M").font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.horizontal, 9)
                        .frame(height: 26)
                        .background {
                            if family == selected {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Tokens.accentGradient)
                            }
                        }
                        .foregroundStyle(family == selected ? AnyShapeStyle(Color.white)
                                                            : AnyShapeStyle(.primary))
                        .contentShape(.rect)
                        .onTapGesture { selected = family }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)
        }
    }

    private var previewPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField("", text: $sampleText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(8)
                    .sunkenSurface(radius: 7)

                Text(sampleText)
                    .font(.custom(selected, size: size))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                Divider()

                ForEach([11.0, 13, 15, 17, 22], id: \.self) { s in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(Int(s))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 22, alignment: .trailing)
                        Text(sampleText)
                            .font(.custom(selected, size: s))
                            .lineLimit(1)
                    }
                }

                Divider()

                ForEach(faces, id: \.self) { face in
                    HStack(spacing: 12) {
                        Text(face)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .frame(width: 110, alignment: .leading)
                        Text("Aa 敏捷 123")
                            .font(.custom(face, size: 17))
                            .lineLimit(1)
                    }
                }
            }
            .padding(Tokens.padCard)
        }
        .scrollIndicators(.never)
    }

    // MARK: -

    private var filtered: [String] {
        let base = monoOnly ? Self.families.filter { Self.monoFamilies.contains($0) }
                            : Self.families
        guard !query.trimmed.isEmpty else { return base }
        return base.filter { $0.localizedCaseInsensitiveContains(query.trimmed) }
    }

    /// 该字族下的具体字重 / 样式
    private var faces: [String] {
        (NSFontManager.shared.availableMembers(ofFontFamily: selected) ?? [])
            .compactMap { $0.first as? String }
            .prefix(8)
            .map { $0 }
    }

    private var codeSnippet: String {
        ".font(.custom(\"\(selected)\", size: \(Int(size))))"
    }

    private var codeRows: [(String, String)] {
        [
            ("SwiftUI", codeSnippet),
            ("AppKit", "NSFont(name: \"\(selected)\", size: \(Int(size)))"),
            ("CSS", "font-family: \"\(selected)\", sans-serif; font-size: \(Int(size))px;"),
        ]
    }

    private var status: StatusLine {
        let isMono = Self.monoFamilies.contains(selected)
        let faceCount = faces.count
        return StatusLine(
            level: .ok,
            text: "\(selected) · \(faceCount) 个字重/样式\(isMono ? " · 等宽，适合代码区" : "")",
            trailing: "\(Self.monoFamilies.count) 个等宽字族", trailingKey: "⌄"
        )
    }
}
