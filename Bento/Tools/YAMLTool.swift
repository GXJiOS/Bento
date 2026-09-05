import SwiftUI

struct YAMLTool: ToolView {
    static let meta = ToolMeta(
        id: "yaml", name: "YAML 互转", category: .formatting, layout: .dual,
        symbol: "list.bullet.indent",
        aliases: ["yaml", "yml", "hz", "huzhuan"]
    )

    private static let sampleYAML = """
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: bento-api
          labels:
            app: bento
        spec:
          replicas: 3
          template:
            spec:
              containers:
                - name: api
                  image: bento/api:1.2.0
                  ports:
                    - containerPort: 8080
                  env:
                    - name: LOG_LEVEL
                      value: debug
        """

    @State private var input = YAMLTool.sampleYAML
    @State private var direction: ConvertDirection = .decode   // decode = YAML → JSON
    @State private var indent = 2

    init() {}

    var body: some View {
        ConverterView(
            input: $input,
            output: result.text,
            error: result.error,
            category: .formatting,
            placeholder: direction == .decode ? "粘贴 YAML…" : "粘贴 JSON…",
            okText: direction == .decode ? "已转为 JSON" : "已转为 YAML",
            trailing: "子集解析",
            onSwap: { let out = result.text; direction = direction.toggled; input = out },
            memoryKey: Self.meta.id
        ) {
            OptionLabel(text: "方向")
            BentoSegments(options: [(ConvertDirection.decode, "YAML → JSON"),
                                    (.encode, "JSON → YAML")],
                          selection: $direction, accent: true)
            if direction == .decode {
                OptionLabel(text: "缩进")
                BentoSegments(options: [(2, "2"), (4, "4")], selection: $indent)
            }
            Spacer()
            Text("不支持锚点 / 多文档 / 复杂键")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
                .help("完整 YAML 规范过大，这里只实现日常配置文件常用的子集；遇到不支持的写法会明确报错")
        }
    }

    private var result: (text: String, error: String?) {
        let src = input.trimmed
        guard !src.isEmpty else { return ("", nil) }

        if direction == .decode {
            do {
                let obj = try YAMLLite.parse(input)
                let opts: JSONSerialization.WritingOptions =
                    [.prettyPrinted, .withoutEscapingSlashes, .fragmentsAllowed, .sortedKeys]
                guard let data = try? JSONSerialization.data(withJSONObject: obj, options: opts),
                      var s = String(data: data, encoding: .utf8) else {
                    return ("", "解析出的结构无法序列化为 JSON")
                }
                if indent == 4 {
                    s = s.components(separatedBy: "\n").map { line -> String in
                        let n = line.prefix(while: { $0 == " " }).count
                        return String(repeating: " ", count: n * 2) + line.dropFirst(n)
                    }.joined(separator: "\n")
                }
                return (s, nil)
            } catch {
                return ("", error.localizedDescription)
            }
        } else {
            guard let data = src.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data,
                                                              options: [.fragmentsAllowed]) else {
                return ("", "输入不是有效的 JSON")
            }
            return (YAMLLite.dump(obj), nil)
        }
    }
}
