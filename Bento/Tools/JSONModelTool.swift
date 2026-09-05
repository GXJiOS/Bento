import SwiftUI

/// 整个 App 最有价值的单点功能：把接口返回的 JSON 变成能直接粘进项目的模型代码。
struct JSONModelTool: ToolView {
    static let meta = ToolMeta(
        id: "json2model", name: "JSON → 模型", category: .formatting, layout: .dual,
        symbol: "shippingbox",
        aliases: ["model", "codable", "json2model", "mx", "moxing", "dto"]
    )

    private static let sample = """
        {
          "user_id": 1024,
          "nick_name": "gxj",
          "avatar_url": null,
          "score": 98.5,
          "is_vip": true,
          "tags": ["swift", "flutter"],
          "orders": [
            {"order_no": "A1", "amount": 12.5, "paid": true},
            {"order_no": "A2", "amount": 30, "paid": false, "note": "加急"}
          ]
        }
        """

    @State private var input = JSONModelTool.sample
    @State private var language: CodeLanguage = .swift
    @State private var camelize = true
    @State private var rootName = "Response"

    init() {}

    var body: some View {
        let r = computed
        ConverterView(
            input: $input,
            output: r.text,
            error: r.error,
            category: .formatting,
            placeholder: "粘贴接口返回的 JSON…",
            okText: "已生成 \(r.types) 个类型" + (r.notes > 0 ? " · \(r.notes) 条提示" : ""),
            trailing: language.label,
            memoryKey: Self.meta.id
        ) {
            OptionLabel(text: "语言")
            BentoSegments(options: CodeLanguage.allCases.map { ($0, $0.label) },
                          selection: $language)
            OptionLabel(text: "根类型")
            TextField("Response", text: $rootName)
                .textFieldStyle(.plain)
                .font(Tokens.mono)
                .padding(.horizontal, 9)
                .frame(width: 120, height: 26)
                .sunkenSurface(radius: 6)
            // TS 没有键名映射机制，改了属性名就对不上 JSON.parse 的结果，故不提供该选项
            if language != .typescript {
                BentoCheck(label: "snake_case → camelCase", isOn: $camelize)
            }
            Spacer()
        }
    }

    private var computed: (text: String, error: String?, types: Int, notes: Int) {
        let src = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !src.isEmpty else { return ("", nil, 0, 0) }
        guard let data = src.data(using: .utf8) else { return ("", "输入不是有效的 UTF-8", 0, 0) }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            let ns = error as NSError
            let desc = ns.userInfo[NSDebugDescriptionErrorKey] as? String ?? ns.localizedDescription
            return ("", "JSON 解析失败 · \(desc)", 0, 0)
        }

        // 顶层是数组时，按元素推断，生成的仍是单个模型
        let name = rootName.isEmpty ? "Response" : rootName
        let inference = JSONInference()
        let rootType: JType
        if let arr = object as? [Any] {
            guard !arr.isEmpty else { return ("", "顶层是空数组，无法推断字段", 0, 0) }
            rootType = inference.infer(arr, name: name)
        } else if object is [String: Any] {
            rootType = inference.infer(object, name: name)
        } else {
            return ("", "顶层不是对象或数组 · 没有可生成的模型", 0, 0)
        }

        guard !inference.shapes.isEmpty else {
            return ("", "没有推断出任何对象类型", 0, 0)
        }

        var code = CodeEmitter(inference: inference, language: language, camelize: camelize).emit()

        // 顶层是数组时补一行提示，告诉你实际该解成什么
        if case .array = rootType {
            let hint: String
            switch language {
            case .swift:      hint = "// 顶层是数组：try JSONDecoder().decode([\(inference.pascal(name))].self, from: data)"
            case .typescript: hint = "// 顶层是数组：\(inference.pascal(name))[]"
            case .kotlin:     hint = "// 顶层是数组：Json.decodeFromString<List<\(inference.pascal(name))>>(text)"
            case .dartFreezed, .dartPlain:
                hint = "// 顶层是数组：(json as List).map((e) => \(inference.pascal(name)).fromJson(e)).toList()"
            }
            code = hint + "\n\n" + code
        }

        // 推断过程中的不确定之处直接写进产物 —— 生成器最怕的就是悄悄猜错
        if !inference.notes.isEmpty {
            code += "\n\n" + inference.notes.map { "// ⚠︎ \($0)" }.joined(separator: "\n")
        }
        return (code, nil, inference.shapes.count, inference.notes.count)
    }
}
