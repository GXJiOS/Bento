import SwiftUI

struct JSONDiffTool: ToolView {
    static let meta = ToolMeta(
        id: "jsondiff", name: "JSON Diff", category: .formatting, layout: .stacked,
        symbol: "arrow.triangle.branch",
        aliases: ["jsondiff", "jdiff", "jsondb"]
    )

    enum Kind { case added, removed, changed, typeChanged }

    struct Change: Identifiable {
        let id = UUID()
        let kind: Kind
        let path: String
        let before: String
        let after: String
    }

    @State private var left = #"{"id":1,"name":"gxj","tags":["a","b"],"meta":{"vip":true,"age":30}}"#
    @State private var right = #"{"id":"1","name":"gxj","tags":["a","c","d"],"meta":{"vip":false}}"#
    @State private var ignoreArrayOrder = false

    init() {}

    var body: some View {
        CompareLayout(
            status: status, left: $left, right: $right,
            leftMeta: leftError == nil ? "有效 JSON" : "解析失败",
            rightMeta: rightError == nil ? "有效 JSON" : "解析失败"
        ) {
            OptionLabel(text: "比较")
            BentoCheck(label: "忽略数组顺序", isOn: $ignoreArrayOrder)
            Spacer()
            Text("按路径逐层比较").font(.system(size: 12)).foregroundStyle(.tertiary)
        } result: {
            Card(title: "差异", dot: ToolCategory.formatting.tint, meta: summary) {
                if let err = leftError ?? rightError {
                    Text(err)
                        .font(Tokens.body).foregroundStyle(Tokens.error)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(Tokens.padCard)
                } else if changes.isEmpty {
                    Text("两侧结构与取值完全一致")
                        .font(Tokens.body).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(changes) { changeRow($0) }
                        }
                    }
                    .scrollIndicators(.never)
                }
            }
        }
    }

    private func changeRow(_ c: Change) -> some View {
        HStack(spacing: 12) {
            Text(badge(c.kind))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color(c.kind))
                .frame(width: 46)
                .padding(.vertical, 2)
                .background(color(c.kind).opacity(0.16), in: .rect(cornerRadius: 4))

            Text(c.path)
                .font(Tokens.mono)
                .frame(width: 190, alignment: .leading)
                .lineLimit(1).truncationMode(.middle)

            if c.kind != .added {
                Text(c.before).font(Tokens.mono).foregroundStyle(Tokens.error).lineLimit(1)
            }
            if c.kind == .changed || c.kind == .typeChanged {
                Image(systemName: "arrow.right")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            if c.kind != .removed {
                Text(c.after).font(Tokens.mono).foregroundStyle(Tokens.ok).lineLimit(1)
            }
            Spacer(minLength: 0)
            CopyButton(value: c.path)
        }
        .padding(.horizontal, Tokens.padCard)
        .frame(height: 30)
        .overlay(alignment: .top) { Rectangle().fill(Tokens.separator).frame(height: 0.5) }
    }

    private func badge(_ k: Kind) -> String {
        switch k {
        case .added: return "新增"
        case .removed: return "删除"
        case .changed: return "变更"
        case .typeChanged: return "类型"
        }
    }

    private func color(_ k: Kind) -> Color {
        switch k {
        case .added: return Tokens.ok
        case .removed: return Tokens.error
        case .changed: return Tokens.warning
        case .typeChanged: return Color(nsColor: .systemPurple)
        }
    }

    // MARK: - 比较

    private func parse(_ s: String) -> Any? {
        guard let d = s.trimmed.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed])
    }

    private var leftError: String? {
        left.trimmed.isEmpty ? nil : (parse(left) == nil ? "左侧不是有效 JSON" : nil)
    }
    private var rightError: String? {
        right.trimmed.isEmpty ? nil : (parse(right) == nil ? "右侧不是有效 JSON" : nil)
    }

    private var changes: [Change] {
        guard let a = parse(left), let b = parse(right) else { return [] }
        var out: [Change] = []
        compare(a, b, path: "$", into: &out)
        return out
    }

    private func compare(_ a: Any, _ b: Any, path: String, into out: inout [Change]) {
        // 类型不同直接记一条，不再深入
        if Self.typeName(a) != Self.typeName(b) {
            out.append(Change(kind: .typeChanged, path: path,
                              before: "\(Self.desc(a)) : \(Self.typeName(a))",
                              after: "\(Self.desc(b)) : \(Self.typeName(b))"))
            return
        }

        switch (a, b) {
        case let (da as [String: Any], db as [String: Any]):
            for key in Set(da.keys).union(db.keys).sorted() {
                let p = "\(path).\(key)"
                switch (da[key], db[key]) {
                case let (x?, y?): compare(x, y, path: p, into: &out)
                case let (x?, nil): out.append(Change(kind: .removed, path: p,
                                                      before: Self.desc(x), after: ""))
                case let (nil, y?): out.append(Change(kind: .added, path: p,
                                                      before: "", after: Self.desc(y)))
                default: break
                }
            }

        case let (aa as [Any], ab as [Any]):
            if ignoreArrayOrder {
                let sa = aa.map(Self.desc).sorted(), sb = ab.map(Self.desc).sorted()
                if sa != sb {
                    for v in sb where !sa.contains(v) {
                        out.append(Change(kind: .added, path: "\(path)[]", before: "", after: v))
                    }
                    for v in sa where !sb.contains(v) {
                        out.append(Change(kind: .removed, path: "\(path)[]", before: v, after: ""))
                    }
                }
            } else {
                for i in 0..<max(aa.count, ab.count) {
                    let p = "\(path)[\(i)]"
                    if i < aa.count && i < ab.count {
                        compare(aa[i], ab[i], path: p, into: &out)
                    } else if i < aa.count {
                        out.append(Change(kind: .removed, path: p,
                                          before: Self.desc(aa[i]), after: ""))
                    } else {
                        out.append(Change(kind: .added, path: p,
                                          before: "", after: Self.desc(ab[i])))
                    }
                }
            }

        default:
            if Self.desc(a) != Self.desc(b) {
                out.append(Change(kind: .changed, path: path,
                                  before: Self.desc(a), after: Self.desc(b)))
            }
        }
    }

    private static func typeName(_ v: Any) -> String {
        switch v {
        case is NSNull: return "null"
        case let n as NSNumber:
            return CFGetTypeID(n) == CFBooleanGetTypeID() ? "bool" : "number"
        case is String: return "string"
        case is [Any]: return "array"
        case is [String: Any]: return "object"
        default: return "?"
        }
    }

    private static func desc(_ v: Any) -> String {
        switch v {
        case is NSNull: return "null"
        case let n as NSNumber:
            return CFGetTypeID(n) == CFBooleanGetTypeID() ? (n.boolValue ? "true" : "false")
                                                          : "\(n)"
        case let s as String: return "\"\(s)\""
        case let a as [Any]: return "[\(a.count) 项]"
        case let d as [String: Any]: return "{\(d.count) 键}"
        default: return "\(v)"
        }
    }

    private var summary: String {
        guard leftError == nil, rightError == nil else { return "—" }
        let a = changes.filter { $0.kind == .added }.count
        let r = changes.filter { $0.kind == .removed }.count
        let c = changes.count - a - r
        return "+\(a)  −\(r)  ~\(c)"
    }

    private var status: StatusLine {
        if let err = leftError ?? rightError {
            return StatusLine(level: .error, text: err, trailing: "JSON", trailingKey: "⌄")
        }
        if left.trimmed.isEmpty || right.trimmed.isEmpty {
            return StatusLine(level: .idle, text: "两侧都填上 JSON 才能比较",
                              trailing: "JSON", trailingKey: "⌄")
        }
        if changes.isEmpty {
            return StatusLine(level: .ok, text: "完全一致", trailing: "JSON", trailingKey: "⌄")
        }
        return StatusLine(level: .warning, text: "发现 \(changes.count) 处差异",
                          trailing: "JSON", trailingKey: "⌄")
    }
}
