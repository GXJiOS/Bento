import Foundation

/// 行级文本 diff。纯逻辑，可脱离 App 验证。
enum TextDiff {

    enum Kind {
        case same, added, removed
    }

    struct Row: Identifiable, Equatable {
        let id = UUID()
        let kind: Kind
        let oldNo: Int?
        let newNo: Int?
        let text: String

        static func == (a: Row, b: Row) -> Bool { a.id == b.id }
    }

    /// 并排视图的一行：左右各自可能为空（对面没有对应行时留占位）
    struct Pair: Identifiable {
        let id = UUID()
        let left: Row?
        let right: Row?

        var isSame: Bool { left?.kind == .same }
        /// 左右都有内容 → 这是「改」，不是「删 + 增」
        var isModified: Bool { left != nil && right != nil && !isSame }
    }

    struct Options {
        var ignoreWhitespace = false
        var ignoreCase = false
    }

    // MARK: - 计算差异

    /// 归一化只用于**比较**，显示的始终是原文
    private static func normalize(_ s: String, _ o: Options) -> String {
        var t = s
        if o.ignoreWhitespace { t = t.filter { !$0.isWhitespace } }
        if o.ignoreCase { t = t.lowercased() }
        return t
    }

    /// 用标准库的 `CollectionDifference`（Myers 算法），比自己搭 O(nm) 的 LCS 表快得多
    static func rows(old: [String], new: [String], options: Options = Options()) -> [Row] {
        let diff = new.map { normalize($0, options) }
            .difference(from: old.map { normalize($0, options) })

        var removedOffsets = Set<Int>()
        var insertedOffsets = Set<Int>()
        for change in diff {
            switch change {
            case .remove(let offset, _, _): removedOffsets.insert(offset)
            case .insert(let offset, _, _): insertedOffsets.insert(offset)
            }
        }

        var out: [Row] = []
        var oi = 0, ni = 0
        while oi < old.count || ni < new.count {
            if ni < new.count, insertedOffsets.contains(ni) {
                out.append(Row(kind: .added, oldNo: nil, newNo: ni + 1, text: new[ni]))
                ni += 1
            } else if oi < old.count, removedOffsets.contains(oi) {
                out.append(Row(kind: .removed, oldNo: oi + 1, newNo: nil, text: old[oi]))
                oi += 1
            } else if oi < old.count, ni < new.count {
                out.append(Row(kind: .same, oldNo: oi + 1, newNo: ni + 1, text: old[oi]))
                oi += 1; ni += 1
            } else if oi < old.count {
                out.append(Row(kind: .removed, oldNo: oi + 1, newNo: nil, text: old[oi]))
                oi += 1
            } else {
                out.append(Row(kind: .added, oldNo: nil, newNo: ni + 1, text: new[ni]))
                ni += 1
            }
        }
        return out
    }

    // MARK: - 配对（并排视图用）

    /// 把线性结果配成左右两列。
    ///
    /// 关键：一段连续的「删除 + 新增」其实是「修改」，要让它们落在**同一水平线**上
    /// 左右对照；数量不等时多出来的一边配空占位。不做这步两列就整体错位，
    /// 并排也就没意义了。
    static func pairs(_ rows: [Row]) -> [Pair] {
        var out: [Pair] = []
        var i = 0
        while i < rows.count {
            if rows[i].kind == .same {
                out.append(Pair(left: rows[i], right: rows[i]))
                i += 1
                continue
            }
            // 收一整段连续差异 —— added / removed 可能交错，取决于遍历顺序
            var block: [Row] = []
            while i < rows.count, rows[i].kind != .same {
                block.append(rows[i])
                i += 1
            }
            let removed = block.filter { $0.kind == .removed }
            let added = block.filter { $0.kind == .added }
            for j in 0..<max(removed.count, added.count) {
                out.append(Pair(left: j < removed.count ? removed[j] : nil,
                                right: j < added.count ? added[j] : nil))
            }
        }
        return out
    }

    static func summary(_ rows: [Row]) -> (added: Int, removed: Int, same: Int) {
        (rows.filter { $0.kind == .added }.count,
         rows.filter { $0.kind == .removed }.count,
         rows.filter { $0.kind == .same }.count)
    }
}


extension Character {
    /// 等宽字体里中日韩字符占两个字宽，估算文本宽度时要算上
    var isCJK: Bool {
        guard let v = unicodeScalars.first?.value else { return false }
        return (0x4E00...0x9FFF).contains(v)       // 中日韩统一表意文字
            || (0x3000...0x303F).contains(v)       // 中日韩符号和标点
            || (0xFF00...0xFFEF).contains(v)       // 全角字符
            || (0x3040...0x30FF).contains(v)       // 日文假名
            || (0xAC00...0xD7AF).contains(v)       // 韩文
    }
}
