import SwiftUI
import Observation

@Observable
final class AppState {

    /// App 级单例。热键回调、Services、CLI 都在 SwiftUI 视图树之外，
    /// 需要一个稳定的入口拿到状态；单窗口工具 App 里这个妥协是值得的。
    static let shared = AppState()

    /// 剪贴板监听服务
    let clipboard = ClipboardMonitor()

    // MARK: - 持久化模型

    /// 落盘的那部分状态。加字段时给默认值，老配置文件才能继续解出来。
    struct Persisted: Codable {
        var favorites: [String] = [ColorTool.meta.id, Base64Tool.meta.id]
        var recents: [String] = []
        var expanded: [String] = ["encoding", "formatting", "style"]
        var hidden: [String] = []
        var selectedToolID: String?
        var sidebarWidth: Double = Double(Tokens.sidebarW)
    }

    struct Settings: Codable {
        var hotKeyCombo = GlobalHotKey.Combo.optionSpace
        var clipboardAutoStart = true
        var clipboardInterval: Double = 0.4
        var clipboardSkipConcealed = true
        var clipboardPersistHistory = false     // 默认不落盘，隐私优先
        var rememberToolInputs = true
        var confirmBeforeQuit = false
    }

    // MARK: - 状态

    var selectedToolID: String?
    var favorites: [String] = []
    private(set) var recents: [String] = []
    var expanded: Set<ToolCategory> = []
    /// 藏起来的工具，侧栏和命令面板都不显示
    var hidden: Set<String> = []

    var settings = Settings() {
        didSet { applySettings(); scheduleSave() }
    }

    var paletteOpen = false
    var paletteQuery = ""
    var sidebarQuery = ""

    /// 工具链：等待被下一个工具消费的输入
    var pendingInput: String?
    var pendingFromTool: String?

    var hotKeyRegistered = false

    // 兼容旧调用点
    var hotKeyCombo: GlobalHotKey.Combo {
        get { settings.hotKeyCombo }
        set { settings.hotKeyCombo = newValue }
    }
    var clipboardAutoStart: Bool { settings.clipboardAutoStart }

    private var saveWorkItem: DispatchWorkItem?

    // MARK: - 生命周期

    private init() {
        let persisted = Persistence.load(Persisted.self, from: .state) ?? Persisted()
        let loaded = Persistence.load(Settings.self, from: .settings) ?? Settings()

        // 注册表变了之后，配置里可能残留已经不存在的工具 id，读进来时过滤掉
        favorites = persisted.favorites.filter { ToolRegistry.entry(id: $0) != nil }
        recents = persisted.recents.filter { ToolRegistry.entry(id: $0) != nil }
        hidden = Set(persisted.hidden.filter { ToolRegistry.entry(id: $0) != nil })
        expanded = Set(persisted.expanded.compactMap { ToolCategory(rawValue: $0) })
        selectedToolID = persisted.selectedToolID.flatMap {
            ToolRegistry.entry(id: $0) != nil ? $0 : nil
        } ?? Base64Tool.meta.id

        settings = loaded
        applySettings()
    }

    private func applySettings() {
        clipboard.interval = settings.clipboardInterval
        clipboard.skipConcealed = settings.clipboardSkipConcealed
        clipboard.persistHistory = settings.clipboardPersistHistory
        clipboard.restartTimerIfNeeded()
        ToolMemory.shared.enabled = settings.rememberToolInputs
    }

    // MARK: - 保存（防抖）

    /// 每次点击都写盘太浪费，攒 0.6 秒
    func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func saveNow() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        Persistence.save(Persisted(
            favorites: favorites,
            recents: recents,
            expanded: expanded.map(\.rawValue).sorted(),
            hidden: hidden.sorted(),
            selectedToolID: selectedToolID
        ), to: .state)
        Persistence.save(settings, to: .settings)
        ToolMemory.shared.flush()
        clipboard.persistIfNeeded()
    }

    // MARK: - 操作

    /// 把当前输出送到另一个工具（工具链）
    func pipe(_ text: String, to toolID: String, from: String? = nil) {
        pendingInput = text
        pendingFromTool = from
        select(toolID)
    }

    /// 工具在 onAppear 里调用，取走属于自己的输入
    func consumePendingInput() -> String? {
        defer { pendingInput = nil; pendingFromTool = nil }
        return pendingInput
    }

    func select(_ id: String) {
        guard ToolRegistry.entry(id: id) != nil else { return }
        selectedToolID = id
        recents.removeAll { $0 == id }
        recents.insert(id, at: 0)
        if recents.count > 8 { recents.removeLast(recents.count - 8) }
        if let cat = ToolRegistry.item(id: id)?.category { expanded.insert(cat) }
        scheduleSave()
    }

    func toggleFavorite(_ id: String) {
        if let i = favorites.firstIndex(of: id) { favorites.remove(at: i) }
        else { favorites.append(id) }
        scheduleSave()
    }

    func isFavorite(_ id: String) -> Bool { favorites.contains(id) }

    func moveFavorite(from source: IndexSet, to destination: Int) {
        favorites.move(fromOffsets: source, toOffset: destination)
        scheduleSave()
    }

    func toggleHidden(_ id: String) {
        if hidden.contains(id) { hidden.remove(id) } else { hidden.insert(id) }
        // 藏掉当前工具就换一个显示
        if hidden.contains(selectedToolID ?? "") {
            selectedToolID = ToolRegistry.all.first { !hidden.contains($0.id) }?.id
        }
        scheduleSave()
    }

    func toggleCategory(_ c: ToolCategory) {
        if expanded.contains(c) { expanded.remove(c) } else { expanded.insert(c) }
        scheduleSave()
    }

    func resetAll() {
        Persistence.deleteAll()
        ToolMemory.shared.clear()
        favorites = Persisted().favorites
        recents = []
        hidden = []
        expanded = Set(Persisted().expanded.compactMap { ToolCategory(rawValue: $0) })
        settings = Settings()
        selectedToolID = Base64Tool.meta.id
    }

    // MARK: - 派生

    var selectedEntry: ToolEntry? {
        selectedToolID.flatMap { ToolRegistry.entry(id: $0) }
    }
    var selectedMeta: ToolMeta? { selectedEntry?.meta }

    var favoriteItems: [ToolItem] {
        favorites.compactMap { ToolRegistry.item(id: $0) }.filter { !hidden.contains($0.id) }
    }
    var recentItems: [ToolItem] {
        recents.compactMap { ToolRegistry.item(id: $0) }.filter { !hidden.contains($0.id) }
    }

    func visibleItems(in category: ToolCategory) -> [ToolItem] {
        ToolRegistry.items(in: category).filter { !hidden.contains($0.id) }
    }

    /// 命令面板搜索：在名称/别名匹配的基础上，把最近用过的往前提
    func search(_ query: String) -> [ToolItem] {
        let base = ToolRegistry.search(query).filter { !hidden.contains($0.id) }
        guard !recents.isEmpty else { return base }
        let rank = Dictionary(uniqueKeysWithValues: recents.enumerated().map { ($1, $0) })
        return base.enumerated().sorted { a, b in
            let ra = rank[a.element.id].map { Double($0) * 0.5 } ?? 999
            let rb = rank[b.element.id].map { Double($0) * 0.5 } ?? 999
            let sa = Double(a.offset) + ra
            let sb = Double(b.offset) + rb
            return sa < sb
        }.map(\.element)
    }
}
