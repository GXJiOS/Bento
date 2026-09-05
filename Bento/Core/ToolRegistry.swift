import SwiftUI

/// 侧栏 / 命令面板统一的行模型。已实现的工具和路线图上的占位共用它。
struct ToolItem: Identifiable, Hashable {
    let id: String
    let name: String
    let category: ToolCategory
    let symbol: String
    let implemented: Bool
    var aliases: [String] = []

    static func == (a: ToolItem, b: ToolItem) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum ToolRegistry {

    // MARK: - 已实现

    /// 新增工具只改这一行 + 加一个文件。
    static let all: [ToolEntry] = [
        // Phase 1 · 编解码（10/10）
        ToolEntry(Base64Tool.self),
        ToolEntry(URLTool.self),
        ToolEntry(UnicodeTool.self),
        ToolEntry(HTMLEntityTool.self),
        ToolEntry(StringEscapeTool.self),
        ToolEntry(JWTTool.self),
        ToolEntry(TimestampTool.self),
        ToolEntry(RadixTool.self),
        ToolEntry(UUIDTool.self),
        ToolEntry(HashTool.self),
        // Phase 2 · 格式化 / 代码
        ToolEntry(JSONTool.self),
        ToolEntry(JSONModelTool.self),
        ToolEntry(JSONDiffTool.self),
        ToolEntry(JSONTreeTool.self),
        ToolEntry(CaseTool.self),
        ToolEntry(TextDiffTool.self),
        ToolEntry(YAMLTool.self),
        ToolEntry(CronTool.self),
        ToolEntry(MarkdownTool.self),
        ToolEntry(RegexTool.self),
        ToolEntry(ColorTool.self),
        ToolEntry(ContrastTool.self),
        ToolEntry(PaletteTool.self),
        ToolEntry(ShadowTool.self),
        ToolEntry(GradientTool.self),
        ToolEntry(CSSTool.self),
        ToolEntry(ScreenPickerTool.self),
        ToolEntry(TypeScaleTool.self),
        ToolEntry(UnitTool.self),
        ToolEntry(GridTool.self),
        ToolEntry(FontTool.self),
        // Phase 4 · 图像与资源
        ToolEntry(ImageConvertTool.self),
        ToolEntry(IconTool.self),
        ToolEntry(ExifTool.self),
        ToolEntry(ImageBase64Tool.self),
        ToolEntry(QRCodeTool.self),
        ToolEntry(SVGTool.self),
        ToolEntry(LottieTool.self),
        // Phase 5 · 系统集成
        ToolEntry(ClipboardMonitorTool.self),
        ToolEntry(ClipboardHistoryTool.self),
        ToolEntry(ServicesTool.self),
        ToolEntry(HotKeyTool.self),
        ToolEntry(ShortcutsTool.self),
        ToolEntry(CLITool.self),
        ToolEntry(DropHubTool.self),
        ToolEntry(PipelineTool.self),
        // Phase 6 · 网络
        ToolEntry(HTTPTool.self),
        ToolEntry(HeaderTool.self),
        ToolEntry(WebSocketTool.self),
        ToolEntry(IPInfoTool.self),
        ToolEntry(DNSTool.self),
        ToolEntry(CertTool.self),
        ToolEntry(EasingTool.self),
    ]

    static func entry(id: String) -> ToolEntry? {
        all.first { $0.id == id }
    }

    // MARK: - 路线图占位（Phase 1+ 逐个替换成真实现）

    /// (名称, 分类) —— 侧栏灰色显示，点击不可用。全部实现后这里就空了。
    private static let planned: [(String, ToolCategory)] = [
    ]

    // MARK: - 合并视图

    /// 已实现的在前，路线图占位在后，各自按分类归组
    static let items: [ToolItem] = {
        let real = all.map {
            ToolItem(id: $0.meta.id, name: $0.meta.name, category: $0.meta.category,
                     symbol: $0.meta.symbol, implemented: true, aliases: $0.meta.aliases)
        }
        let todo = planned.map { name, cat in
            ToolItem(id: "todo.\(cat.rawValue).\(name)", name: name, category: cat,
                     symbol: cat.symbol, implemented: false)
        }
        return real + todo
    }()

    static func items(in category: ToolCategory) -> [ToolItem] {
        items.filter { $0.category == category }
    }

    static func item(id: String) -> ToolItem? {
        items.first { $0.id == id }
    }

    static var implementedCount: Int { all.count }
    static var totalCount: Int { items.count }

    // MARK: - 搜索（工具名 + 英文别名 + 拼音首字母，三路并行）

    static func search(_ query: String) -> [ToolItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else {
            return items.filter(\.implemented)
        }
        return items
            .compactMap { item -> (ToolItem, Int)? in
                guard let rank = rank(item, q) else { return nil }
                return (item, rank)
            }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 < b.1 }
                // 同权重时已实现的排前面
                if a.0.implemented != b.0.implemented { return a.0.implemented }
                return a.0.name < b.0.name
            }
            .map(\.0)
    }

    /// 数字越小越靠前
    private static func rank(_ item: ToolItem, _ q: String) -> Int? {
        let name = item.name.lowercased()
        if name.hasPrefix(q) { return 0 }
        if item.aliases.contains(where: { $0.hasPrefix(q) }) { return 1 }
        if name.contains(q) { return 2 }
        if item.aliases.contains(where: { $0.contains(q) }) { return 3 }
        return nil
    }
}
