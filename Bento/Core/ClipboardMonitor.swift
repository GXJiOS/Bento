import SwiftUI
import AppKit
import Observation

/// 剪贴板监听。
///
/// NSPasteboard 没有变更通知，只能轮询 `changeCount`（一个单调递增的整数）。
/// 0.4s 一次、只比较整数，开销可以忽略；真正读内容只在 changeCount 变了之后发生。
@Observable
final class ClipboardMonitor {

    struct Entry: Identifiable, Equatable, Codable {
        var id = UUID()
        let text: String
        let date: Date
        let kindLabel: String?
        var pinned = false

        static func == (a: Entry, b: Entry) -> Bool { a.id == b.id }

        var preview: String {
            let one = text.replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            return String(one.prefix(120))
        }
    }

    // MARK: - 状态

    private(set) var history: [Entry] = []
    /// 当前剪贴板内容能被哪个工具直接处理
    private(set) var detected: ContentDetector.Hit?
    private(set) var currentText = ""
    private(set) var lastChange: Date?
    private(set) var pollCount = 0

    var isRunning = false
    var interval: Double = 0.4
    var maxHistory = 50
    /// 密码管理器会给内容打 `org.nspasteboard.ConcealedType` 标记，必须跳过
    var skipConcealed = true
    /// 超过这个长度不进历史，避免把一整个文件塞进内存
    var maxLength = 20_000

    /// 默认关：剪贴板里什么都可能有，不该无声无息地写到盘上
    var persistHistory = false {
        didSet {
            if persistHistory { persistIfNeeded() } else { Persistence.delete(.clipboard) }
        }
    }

    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var historyDirty = false

    init() {
        // 只有上次明确开了持久化才会有这个文件
        if let saved = Persistence.load([Entry].self, from: .clipboard) {
            history = saved
            persistHistory = true
        }
    }

    /// 只写置顶项和最近 20 条，别把整个历史摊在盘上
    func persistIfNeeded() {
        guard persistHistory, historyDirty else { return }
        let pinned = history.filter(\.pinned)
        let recent = history.filter { !$0.pinned }.prefix(20)
        Persistence.save(Array(pinned + recent), to: .clipboard)
        historyDirty = false
    }

    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    // MARK: - 控制

    func start() {
        guard !isRunning else { return }
        isRunning = true
        lastChangeCount = NSPasteboard.general.changeCount
        readCurrent()
        scheduleTimer()
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func toggle() { isRunning ? stop() : start() }

    /// 改了间隔要重建 timer
    func restartTimerIfNeeded() {
        guard isRunning else { return }
        timer?.invalidate()
        scheduleTimer()
    }

    private func scheduleTimer() {
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // .common 模式：拖动窗口或滚动时也不会停下来
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        pollCount += 1
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        readCurrent()
    }

    // MARK: - 读取

    private func readCurrent() {
        let pb = NSPasteboard.general

        if skipConcealed, let types = pb.types,
           types.contains(Self.concealedType) || types.contains(Self.transientType) {
            currentText = "（已跳过：被标记为密码 / 临时内容）"
            detected = nil
            return
        }
        guard let text = pb.string(forType: .string), !text.isEmpty else {
            currentText = ""
            detected = nil
            return
        }

        currentText = text
        lastChange = Date()
        detected = ContentDetector.detect(text)
        record(text)
    }

    private func record(_ text: String) {
        guard text.count <= maxLength else { return }
        // 连续复制同一段内容不重复记
        if let first = history.first(where: { !$0.pinned }), first.text == text { return }
        if history.contains(where: { $0.text == text && $0.pinned }) { return }

        history.insert(Entry(text: text, date: Date(), kindLabel: detected?.kindLabel), at: 0)
        historyDirty = true
        trim()
    }

    private func trim() {
        let pinned = history.filter(\.pinned)
        var unpinned = history.filter { !$0.pinned }
        if unpinned.count > maxHistory {
            unpinned.removeLast(unpinned.count - maxHistory)
        }
        // 保持原顺序：按时间重排
        history = (pinned + unpinned).sorted { $0.date > $1.date }
    }

    // MARK: - 历史操作

    func copyBack(_ entry: Entry) {
        // 自己写回剪贴板会让 changeCount 变化，先记下来避免又被自己记一遍
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        lastChangeCount = NSPasteboard.general.changeCount
        currentText = entry.text
        detected = ContentDetector.detect(entry.text)
    }

    func togglePin(_ entry: Entry) {
        guard let i = history.firstIndex(where: { $0.id == entry.id }) else { return }
        history[i].pinned.toggle()
        historyDirty = true
        trim()
    }

    func remove(_ entry: Entry) {
        history.removeAll { $0.id == entry.id }
        historyDirty = true
        persistIfNeeded()
    }

    func clearUnpinned() {
        history.removeAll { !$0.pinned }
        historyDirty = true
        if persistHistory { persistIfNeeded() } else { Persistence.delete(.clipboard) }
    }

    var pinnedCount: Int { history.filter(\.pinned).count }
}
