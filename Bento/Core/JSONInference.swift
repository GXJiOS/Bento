import Foundation

// MARK: - 类型模型

indirect enum JType {
    case string, int, double, bool, null, any
    case array(JType)
    case object(String)     // 指向 Inference.shapes 里的 shape 名

    var isNull: Bool { if case .null = self { return true }; return false }
}

struct FieldInfo {
    var type: JType
    var optional: Bool
}

final class Shape {
    let name: String
    var order: [String] = []
    var fields: [String: FieldInfo] = [:]
    /// 这个 shape 一共被推断了多少次（数组里每个元素算一次）
    var seen = 0
    /// 每个字段出现了多少次。出现次数 < seen ⇒ 不是每个元素都有 ⇒ 可选。
    /// 不能用「本轮缺失就标可选」，因为字段可能到后面的元素才第一次出现。
    var fieldSeen: [String: Int] = [:]

    init(name: String) { self.name = name }

    func put(_ key: String, _ info: FieldInfo) {
        if fields[key] == nil { order.append(key) }
        fields[key] = info
    }
}

// MARK: - 推断

/// 从一段 JSON 推断出结构。
///
/// 难点全在「同一个位置出现不同类型」上：数组里前 3 个元素有 `avatar` 后 2 个没有、
/// 某个字段有时是 int 有时是 null。这里的规则是
/// **缺失或 null ⇒ 可选**、**int + double ⇒ double**、**真冲突 ⇒ any**，
/// 而不是拿第一个元素当模板 —— 后者是大多数在线转换器出错的地方。
final class JSONInference {
    private(set) var shapes: [String: Shape] = [:]
    private(set) var shapeOrder: [String] = []
    /// 推断过程中遇到的、需要提醒用户的情况
    private(set) var notes: [String] = []

    @discardableResult
    func infer(_ value: Any, name: String) -> JType {
        switch value {
        case is NSNull:
            return .null

        case let n as NSNumber:
            // NSNumber 分不清 1 和 true，得看 objCType
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool }
            let t = String(cString: n.objCType)
            return (t == "d" || t == "f") ? .double : .int

        case is String:
            return .string

        case let arr as [Any]:
            guard !arr.isEmpty else {
                notes.append("`\(name)` 是空数组，元素类型无法推断，按 Any 处理")
                return .array(.any)
            }
            let element = singular(name)
            var merged: JType = .null
            for item in arr {
                merged = merge(merged, infer(item, name: element), at: name)
            }
            return .array(merged)

        case let dict as [String: Any]:
            let shapeName = pascal(name)
            let shape = shapes[shapeName] ?? {
                let s = Shape(name: shapeName)
                shapes[shapeName] = s
                shapeOrder.append(shapeName)
                return s
            }()
            shape.seen += 1
            for (key, v) in dict.sorted(by: { lhs, rhs in
                // 原始顺序不可得（JSONSerialization 不保序），退而求其次按键名排
                lhs.key < rhs.key
            }) {
                shape.fieldSeen[key, default: 0] += 1
                let t = infer(v, name: key)
                if let existing = shape.fields[key] {
                    shape.put(key, FieldInfo(type: merge(existing.type, t, at: key),
                                             optional: existing.optional || t.isNull))
                } else {
                    shape.put(key, FieldInfo(type: t, optional: t.isNull))
                }
            }
            return .object(shapeName)

        default:
            return .any
        }
    }

    private var finalized = false

    /// 推断结束后统一结算：出现次数不足的字段标可选、全是 null 的字段给出提示。
    /// emit 时自动调用，幂等。
    func finalize() {
        guard !finalized else { return }
        finalized = true
        for name in shapeOrder {
            guard let shape = shapes[name] else { continue }
            for key in shape.order {
                if (shape.fieldSeen[key] ?? 0) < shape.seen {
                    shape.fields[key]?.optional = true
                }
                if shape.fields[key]?.type.isNull == true {
                    notes.append("`\(key)` 的取值全是 null，类型无从推断，已按 String / unknown 处理")
                }
            }
        }
    }

    // MARK: 类型合并

    private func merge(_ a: JType, _ b: JType, at path: String) -> JType {
        if a.isNull { return b }
        if b.isNull { return a }

        switch (a, b) {
        case (.string, .string):   return .string
        case (.bool, .bool):       return .bool
        case (.int, .int):         return .int
        case (.double, .double), (.int, .double), (.double, .int):
            return .double
        case let (.array(x), .array(y)):
            return .array(merge(x, y, at: path))
        case let (.object(x), .object(y)):
            if x == y { return .object(x) }
            notes.append("`\(path)` 里出现了结构不同的对象，已合并为 \(x)")
            return .object(x)
        case (.any, _), (_, .any):
            return .any
        default:
            notes.append("`\(path)` 出现混合类型，降级为 Any / dynamic")
            return .any
        }
    }

    // MARK: 命名

    /// users → User，boxes → Box，data → DataItem（避免和语言内建类型撞名）
    private func singular(_ s: String) -> String {
        var n = s
        if n.hasSuffix("ies") { n = String(n.dropLast(3)) + "y" }
        else if n.hasSuffix("ses") || n.hasSuffix("xes") { n = String(n.dropLast(2)) }
        else if n.hasSuffix("s") && !n.hasSuffix("ss") { n = String(n.dropLast()) }
        return n
    }

    func pascal(_ s: String) -> String {
        let parts = s.split(whereSeparator: { $0 == "_" || $0 == "-" || $0 == " " || $0 == "." })
        let joined = parts.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
        return joined.isEmpty ? "Item" : joined
    }
}

// MARK: - 代码生成

enum CodeLanguage: String, Hashable, CaseIterable {
    case swift, typescript, dartFreezed, dartPlain, kotlin

    var label: String {
        switch self {
        case .swift:       return "Swift"
        case .typescript:  return "TypeScript"
        case .dartFreezed: return "Dart freezed"
        case .dartPlain:   return "Dart"
        case .kotlin:      return "Kotlin"
        }
    }
}

struct CodeEmitter {
    let inference: JSONInference
    let language: CodeLanguage
    /// snake_case 字段转成 camelCase，并补上映射（CodingKeys / @SerialName / @JsonKey）
    let camelize: Bool

    func emit() -> String {
        inference.finalize()
        var out: [String] = []
        if language == .dartFreezed {
            out.append("import 'package:freezed_annotation/freezed_annotation.dart';\n")
            out.append("part 'model.freezed.dart';")
            out.append("part 'model.g.dart';\n")
        }
        if language == .kotlin {
            out.append("import kotlinx.serialization.SerialName")
            out.append("import kotlinx.serialization.Serializable\n")
        }
        // 反序：嵌套类型先定义，主类型在最后，读起来更顺
        for name in inference.shapeOrder.reversed() {
            guard let shape = inference.shapes[name] else { continue }
            out.append(render(shape))
        }
        return out.joined(separator: "\n")
    }

    // MARK: 单个类型

    private func render(_ shape: Shape) -> String {
        switch language {
        case .swift:       return renderSwift(shape)
        case .typescript:  return renderTS(shape)
        case .dartFreezed: return renderDartFreezed(shape)
        case .dartPlain:   return renderDartPlain(shape)
        case .kotlin:      return renderKotlin(shape)
        }
    }

    private func renderSwift(_ shape: Shape) -> String {
        var lines = ["struct \(shape.name): Codable {"]
        var mappings: [(String, String)] = []
        for key in shape.order {
            guard let f = shape.fields[key] else { continue }
            let prop = camelize ? camel(key) : key
            if prop != key { mappings.append((prop, key)) }
            lines.append("    let \(prop): \(type(f))")
        }
        if !mappings.isEmpty {
            lines.append("")
            lines.append("    enum CodingKeys: String, CodingKey {")
            for key in shape.order {
                let prop = camelize ? camel(key) : key
                lines.append(prop == key ? "        case \(prop)"
                                         : "        case \(prop) = \"\(key)\"")
            }
            lines.append("    }")
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private func renderTS(_ shape: Shape) -> String {
        var lines = ["export interface \(shape.name) {"]
        for key in shape.order {
            guard let f = shape.fields[key] else { continue }
            // TS 用 `?:` 表达可选，比 `| null` 更贴近实际用法
            lines.append("  \(key)\(f.optional ? "?" : ""): \(type(f, bare: true));")
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private func renderDartFreezed(_ shape: Shape) -> String {
        var lines = ["@freezed", "class \(shape.name) with _$\(shape.name) {",
                     "  const factory \(shape.name)({"]
        for key in shape.order {
            guard let f = shape.fields[key] else { continue }
            let prop = camelize ? camel(key) : key
            let anno = prop != key ? "@JsonKey(name: '\(key)') " : ""
            let req = f.optional ? "" : "required "
            lines.append("    \(anno)\(req)\(type(f)) \(prop),")
        }
        lines.append("  }) = _\(shape.name);\n")
        lines.append("  factory \(shape.name).fromJson(Map<String, dynamic> json) =>")
        lines.append("      _$\(shape.name)FromJson(json);")
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private func renderDartPlain(_ shape: Shape) -> String {
        var lines = ["class \(shape.name) {"]
        for key in shape.order {
            guard let f = shape.fields[key] else { continue }
            lines.append("  final \(type(f)) \(camelize ? camel(key) : key);")
        }
        lines.append("")
        lines.append("  \(shape.name)({")
        for key in shape.order {
            guard let f = shape.fields[key] else { continue }
            lines.append("    \(f.optional ? "" : "required ")this.\(camelize ? camel(key) : key),")
        }
        lines.append("  });")
        lines.append("")
        lines.append("  factory \(shape.name).fromJson(Map<String, dynamic> json) => \(shape.name)(")
        for key in shape.order {
            guard let f = shape.fields[key] else { continue }
            lines.append("        \(camelize ? camel(key) : key): \(dartParse(f, key: key)),")
        }
        lines.append("      );")
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private func renderKotlin(_ shape: Shape) -> String {
        var lines = ["@Serializable", "data class \(shape.name)("]
        for (i, key) in shape.order.enumerated() {
            guard let f = shape.fields[key] else { continue }
            let prop = camelize ? camel(key) : key
            let anno = prop != key ? "@SerialName(\"\(key)\") " : ""
            let tail = i == shape.order.count - 1 ? "" : ","
            lines.append("    \(anno)val \(prop): \(type(f))\(f.optional ? " = null" : "")\(tail)")
        }
        lines.append(")")
        return lines.joined(separator: "\n")
    }

    // MARK: 类型名

    private func type(_ f: FieldInfo, bare: Bool = false) -> String {
        let base = typeName(f.type)
        guard f.optional, !bare else { return base }
        // Dart 的 dynamic 本身就允许 null，写 dynamic? 会被分析器警告
        if base == "dynamic" { return base }
        switch language {
        case .swift, .kotlin, .dartFreezed, .dartPlain: return base + "?"
        case .typescript: return base
        }
    }

    private func typeName(_ t: JType) -> String {
        switch t {
        case .string: return map("String", "string", "String", "String")
        case .int:    return map("Int", "number", "int", "Int")
        case .double: return map("Double", "number", "double", "Double")
        case .bool:   return map("Bool", "boolean", "bool", "Boolean")
        // 全是 null 时没有任何类型线索，给一个中性类型 + finalize 里的提示，
        // 不要在这里带 `?`，可选性统一由 FieldInfo.optional 表达（否则会出 String??）
        case .null:   return map("String", "unknown", "dynamic", "String")
        case .any:    return map("AnyCodable", "any", "dynamic", "Any")
        case .array(let e):
            let inner = typeName(e)
            switch language {
            case .swift, .kotlin: return language == .swift ? "[\(inner)]" : "List<\(inner)>"
            case .typescript: return "\(inner)[]"
            case .dartFreezed, .dartPlain: return "List<\(inner)>"
            }
        case .object(let n): return n
        }
    }

    private func map(_ swift: String, _ ts: String, _ dart: String, _ kotlin: String) -> String {
        switch language {
        case .swift: return swift
        case .typescript: return ts
        case .dartFreezed, .dartPlain: return dart
        case .kotlin: return kotlin
        }
    }

    private func dartParse(_ f: FieldInfo, key: String) -> String {
        switch f.type {
        case .object(let n):
            return f.optional
                ? "json['\(key)'] == null ? null : \(n).fromJson(json['\(key)'])"
                : "\(n).fromJson(json['\(key)'])"
        case .array(let e):
            if case .object(let n) = e {
                return "(json['\(key)'] as List\(f.optional ? "?" : ""))\(f.optional ? "?" : "")"
                     + ".map((e) => \(n).fromJson(e)).toList()"
            }
            return "List<\(typeName(e))>.from(json['\(key)'] ?? [])"
        default:
            return "json['\(key)']"
        }
    }

    private func camel(_ s: String) -> String {
        let parts = s.split(whereSeparator: { $0 == "_" || $0 == "-" })
        guard let first = parts.first else { return s }
        return String(first).lowercasedFirst()
            + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    }
}

extension String {
    func lowercasedFirst() -> String { prefix(1).lowercased() + dropFirst() }
    func uppercasedFirst() -> String { prefix(1).uppercased() + dropFirst() }
}
