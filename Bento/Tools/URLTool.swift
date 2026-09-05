import SwiftUI

struct URLTool: ToolView {
    static let meta = ToolMeta(
        id: "url", name: "URL 编解码", category: .encoding, layout: .dual,
        symbol: "link",
        aliases: ["url", "percent", "urlencode", "wz", "ljbm"]
    )

    /// 编码强度。RFC 3986 把字符分成 unreserved / reserved 两类，
    /// 到底编不编 reserved 取决于你是在编「整条 URL」还是「一个参数值」。
    enum Scope: Hashable {
        case component   // 参数值：只留 unreserved，& = ? / 全编
        case query       // 查询串：保留 & =
        case whole       // 整条 URL：保留 :/?#[]@ 等结构字符

        var label: String {
            switch self {
            case .component: return "参数值"
            case .query:     return "查询串"
            case .whole:     return "整条 URL"
            }
        }

        var allowed: CharacterSet {
            switch self {
            case .component:
                return CharacterSet(charactersIn:
                    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
            case .query:
                var s = CharacterSet(charactersIn:
                    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
                s.insert(charactersIn: "&=")
                return s
            case .whole:
                return .urlQueryAllowed.union(CharacterSet(charactersIn: ":/?#[]@!$'()*+,;"))
            }
        }
    }

    @State private var input = "https://example.com/搜索?q=Swift 并发&page=1"
    @State private var direction: ConvertDirection = .encode
    @State private var scope: Scope = .whole
    @State private var plusAsSpace = true

    init() {}

    var body: some View {
        ConverterView(
            input: $input,
            output: result.text,
            error: result.error,
            placeholder: "粘贴一条 URL 或参数值…",
            okText: direction == .encode ? "编码成功" : "解码成功",
            trailing: paramCount,
            memoryKey: Self.meta.id
        ) {
            OptionLabel(text: "方向")
            DirectionPicker(direction: $direction)
            if direction == .encode {
                OptionLabel(text: "范围")
                BentoSegments(options: [(Scope.component, Scope.component.label),
                                        (.query, Scope.query.label),
                                        (.whole, Scope.whole.label)],
                              selection: $scope)
            } else {
                BentoCheck(label: "+ 视为空格", isOn: $plusAsSpace)
            }
        }
    }

    private var result: (text: String, error: String?) {
        guard !input.isEmpty else { return ("", nil) }
        if direction == .encode {
            guard let s = input.addingPercentEncoding(withAllowedCharacters: scope.allowed) else {
                return ("", "无法编码（输入包含无效的 Unicode 标量）")
            }
            return (s, nil)
        } else {
            let src = plusAsSpace ? input.replacingOccurrences(of: "+", with: " ") : input
            guard let s = src.removingPercentEncoding else {
                return ("", "无效的百分号编码 · 出现不完整的 %XX 序列")
            }
            return (s, nil)
        }
    }

    /// 顺手在状态行右侧报出参数个数，省得再开一个工具
    private var paramCount: String {
        let text = direction == .encode ? input : (result.text.isEmpty ? input : result.text)
        guard let q = text.firstIndex(of: "?") else { return "无查询串" }
        let query = text[text.index(after: q)...]
        let n = query.split(separator: "&").count
        return "\(n) 个参数"
    }
}
