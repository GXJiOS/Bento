import Foundation

/// JSON 树模型。
///
/// 渲染时**不用递归 View** —— 那样几万个节点会把 SwiftUI 拖垮。
/// 这里把树按当前展开状态压成一维数组，UI 侧配 LazyVStack 只渲染可见行。
enum JSONTree {

    enum Kind {
        case object(Int)      // 子项数
        case array(Int)
        case string(String)
        case number(String)
        case bool(Bool)
        case null

        var isContainer: Bool {
            switch self {
            case .object, .array: return true
            default: return false
            }
        }

        var childCount: Int {
            switch self {
            case .object(let n), .array(let n): return n
            default: return 0
            }
        }

        /// 折叠时显示的摘要，例如 `{ 4 项 }` / `[ 12 项 ]`
        var collapsedSummary: String {
            switch self {
            case .object(let n): return n == 0 ? "{}" : "{ \(n) 项 }"
            case .array(let n):  return n == 0 ? "[]" : "[ \(n) 项 ]"
            default: return ""
            }
        }

        var typeName: String {
            switch self {
            case .object: return "object"
            case .array:  return "array"
            case .string: return "string"
            case .number: return "number"
            case .bool:   return "bool"
            case .null:   return "null"
            }
        }

        /// 标量的显示文本（字符串带引号，和 JSON 里看到的一致）
        var display: String {
            switch self {
            case .string(let s): return "\"\(s)\""
            case .number(let n): return n
            case .bool(let b):   return b ? "true" : "false"
            case .null:          return "null"
            case .object, .array: return collapsedSummary
            }
        }

        /// 复制值时用的原始文本（字符串不带引号）
        var rawValue: String {
            if case .string(let s) = self { return s }
            return display
        }
    }

    final class Node {
        let path: String          // $.user.roles[0]，天然唯一，直接当 id 用
        let key: String?          // 对象成员名；数组元素为 nil
        let index: Int?           // 数组下标
        let kind: Kind
        let children: [Node]
        let depth: Int

        init(path: String, key: String?, index: Int?, kind: Kind, children: [Node], depth: Int) {
            self.path = path; self.key = key; self.index = index
            self.kind = kind; self.children = children; self.depth = depth
        }

        /// 行首显示的标签
        var label: String {
            if let key { return key }
            if let index { return "\(index)" }
            return "$"
        }
    }

    struct Row: Identifiable {
        let node: Node
        let expanded: Bool
        var id: String { node.path }
    }

    struct Stats {
        var nodes = 0
        var objects = 0
        var arrays = 0
        var scalars = 0
        var maxDepth = 0
    }

    // MARK: - 构建

    /// 超过这个节点数就不再往下展开构建，避免几十 MB 的 JSON 直接把内存吃满
    static let nodeLimit = 50_000

    static func build(_ value: Any, key: String? = nil, index: Int? = nil,
                      path: String = "$", depth: Int = 0,
                      counter: inout Int) -> Node {
        counter += 1
        guard counter < nodeLimit else {
            return Node(path: path, key: key, index: index,
                        kind: .string("…超出节点上限"), children: [], depth: depth)
        }

        switch value {
        case let dict as [String: Any]:
            // JSONSerialization 不保序，按键名排序至少是稳定可预期的
            let children = dict.keys.sorted().map { k in
                build(dict[k]!, key: k, path: "\(path).\(k)", depth: depth + 1, counter: &counter)
            }
            return Node(path: path, key: key, index: index,
                        kind: .object(dict.count), children: children, depth: depth)

        case let arr as [Any]:
            let children = arr.enumerated().map { i, v in
                build(v, index: i, path: "\(path)[\(i)]", depth: depth + 1, counter: &counter)
            }
            return Node(path: path, key: key, index: index,
                        kind: .array(arr.count), children: children, depth: depth)

        case is NSNull:
            return Node(path: path, key: key, index: index, kind: .null, children: [], depth: depth)

        case let n as NSNumber:
            // NSNumber 分不清 1 和 true，看 CFTypeID
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return Node(path: path, key: key, index: index,
                            kind: .bool(n.boolValue), children: [], depth: depth)
            }
            return Node(path: path, key: key, index: index,
                        kind: .number("\(n)"), children: [], depth: depth)

        case let s as String:
            return Node(path: path, key: key, index: index,
                        kind: .string(s), children: [], depth: depth)

        default:
            return Node(path: path, key: key, index: index,
                        kind: .string("\(value)"), children: [], depth: depth)
        }
    }

    struct ParseError: LocalizedError {
        let message: String
        /// 输入为空不算错误，只是还没开始
        var isEmpty: Bool { message.isEmpty }
        var errorDescription: String? { message }
    }

    static func parse(_ text: String) -> Result<Node, ParseError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(ParseError(message: "")) }
        guard let data = trimmed.data(using: .utf8) else {
            return .failure(ParseError(message: "输入不是有效的 UTF-8"))
        }
        do {
            let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            var counter = 0
            return .success(build(obj, counter: &counter))
        } catch {
            let ns = error as NSError
            let desc = ns.userInfo[NSDebugDescriptionErrorKey] as? String ?? ns.localizedDescription
            return .failure(ParseError(message: friendly(desc, in: trimmed)))
        }
    }

    /// 把 NSError 里的字符偏移换算成行列
    private static func friendly(_ desc: String, in src: String) -> String {
        guard let r = desc.range(of: #"character (\d+)"#, options: .regularExpression),
              let offset = Int(desc[r].components(separatedBy: " ").last ?? "") else {
            return "JSON 解析失败 · \(desc)"
        }
        let prefix = src.prefix(offset)
        let line = prefix.components(separatedBy: "\n").count
        let col = (prefix.components(separatedBy: "\n").last?.count ?? 0) + 1
        return "第 \(line) 行第 \(col) 列 · \(desc)"
    }

    // MARK: - 压平

    /// 只输出「祖先都处于展开状态」的节点，配合 LazyVStack 就只渲染可见行
    static func flatten(_ root: Node, expanded: Set<String>, filter: String = "") -> [Row] {
        var out: [Row] = []
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()

        func matches(_ node: Node) -> Bool {
            guard !needle.isEmpty else { return true }
            if node.label.lowercased().contains(needle) { return true }
            if case .string(let s) = node.kind, s.lowercased().contains(needle) { return true }
            if case .number(let n) = node.kind, n.contains(needle) { return true }
            return false
        }

        /// 子树里有没有命中项 —— 有的话父节点也要显示出来，不然看不到上下文
        func subtreeMatches(_ node: Node) -> Bool {
            if matches(node) { return true }
            return node.children.contains { subtreeMatches($0) }
        }

        func walk(_ node: Node) {
            if !needle.isEmpty && !subtreeMatches(node) { return }
            // 搜索时命中路径一律当作展开 —— 既要把子节点带出来，
            // 箭头也得跟着转，否则会出现「箭头是收起的但下面有内容」
            let isExpanded = expanded.contains(node.path) || !needle.isEmpty
            out.append(Row(node: node, expanded: isExpanded))
            guard isExpanded else { return }
            for child in node.children { walk(child) }
        }

        walk(root)
        return out
    }

    /// 所有容器节点的路径 —— 「展开全部」用
    static func allContainerPaths(_ root: Node) -> Set<String> {
        var out = Set<String>()
        func walk(_ n: Node) {
            if n.kind.isContainer { out.insert(n.path) }
            n.children.forEach(walk)
        }
        walk(root)
        return out
    }

    /// 展开到第 n 层（0 = 只有根）
    static func paths(_ root: Node, upTo depth: Int) -> Set<String> {
        var out = Set<String>()
        func walk(_ n: Node) {
            guard n.depth < depth, n.kind.isContainer else { return }
            out.insert(n.path)
            n.children.forEach(walk)
        }
        walk(root)
        return out
    }

    static func stats(_ root: Node) -> Stats {
        var s = Stats()
        func walk(_ n: Node) {
            s.nodes += 1
            s.maxDepth = max(s.maxDepth, n.depth)
            switch n.kind {
            case .object: s.objects += 1
            case .array:  s.arrays += 1
            default:      s.scalars += 1
            }
            n.children.forEach(walk)
        }
        walk(root)
        return s
    }

    /// 把某个子树重新序列化成 JSON 文本 —— 「复制这一段」用
    static func json(_ node: Node, pretty: Bool = true) -> String {
        func rebuild(_ n: Node) -> Any {
            switch n.kind {
            case .object:
                var d: [String: Any] = [:]
                for c in n.children { d[c.key ?? ""] = rebuild(c) }
                return d
            case .array:
                return n.children.map { rebuild($0) }
            case .string(let s): return s
            case .number(let n): return Double(n) ?? n
            case .bool(let b):   return b
            case .null:          return NSNull()
            }
        }
        var opts: JSONSerialization.WritingOptions = [.withoutEscapingSlashes, .fragmentsAllowed]
        if pretty { opts.insert([.prettyPrinted, .sortedKeys]) }
        guard let data = try? JSONSerialization.data(withJSONObject: rebuild(node), options: opts),
              let s = String(data: data, encoding: .utf8) else { return node.kind.display }
        return s
    }
}
