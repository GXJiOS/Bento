import SwiftUI
import UniformTypeIdentifiers

/// `.dual` 工具的公共容器。
///
/// 编解码类工具的骨架完全一样：选项条 + 输入卡 + 输出卡 + 状态行，
/// 差别只在「一个转换函数」和「几个选项控件」。这里把骨架收口，
/// 每个工具就只剩下自己的算法。
struct ConverterView<Options: View>: View {
    @Environment(AppState.self) private var app
    @Binding var input: String
    /// 转换结果；error 非空时输出区留空、状态行转红
    var output: String
    var error: String? = nil

    var category: ToolCategory = .encoding
    var placeholder: String = "在此输入或粘贴…"
    var okText: String = "转换成功"
    var idleText: String = "等待输入"
    var trailing: String = "UTF-8"

    /// 可逆工具传这个，分隔间隙里出现 ⇅
    var onSwap: (() -> Void)? = nil
    /// 需要读文件的工具传这个，输入卡底部出现「载入文件…」
    var onLoadFile: ((URL) -> Void)? = nil
    /// 传工具 id 就会记住上次输入（下次打开自动填回）
    var memoryKey: String? = nil

    @ViewBuilder var options: () -> Options

    var body: some View {
        content
            .onAppear {
                guard let key = memoryKey, input.isEmpty || isDefaultInput,
                      let saved = ToolMemory.shared.value(for: key) else { return }
                input = saved
                isDefaultInput = false
            }
            .onChange(of: input) { _, newValue in
                isDefaultInput = false
                if let key = memoryKey { ToolMemory.shared.set(newValue, for: key) }
            }
    }

    /// 首次出现时输入框里是工具自带的示例值，此时应让记忆覆盖它；
    /// 用户一旦改过就不再覆盖
    @State private var isDefaultInput = true

    private var content: some View {
        DualLayout(status: status, onSwap: onSwap) {
            options()
        } input: {
            Card(title: "INPUT", dot: category.tint, meta: inputMeta) {
                CodeArea(text: $input, placeholder: placeholder)
                CardFooter {
                    Button {
                        input = NSPasteboard.general.string(forType: .string) ?? input
                    } label: {
                        HStack(spacing: 5) { Text("粘贴"); Keycap(text: "⌘⇧V") }
                    }
                    .bentoButton(plain: true)

                    Button {
                        input = ""
                    } label: {
                        HStack(spacing: 5) { Text("清空"); Keycap(text: "⌘⇧K") }
                    }
                    .bentoButton(plain: true)
                    .disabled(input.isEmpty)

                    Spacer()
                    if onLoadFile != nil {
                        Button("载入文件…") { loadFile() }.bentoButton(plain: true)
                    }
                }
            }
        } output: {
            Card(title: "OUTPUT", dot: ToolCategory.image.tint, meta: outputMeta) {
                CodeArea(text: .constant(error == nil ? output : ""), isEditable: false)
                CardFooter {
                    CopyButton(value: output, compact: false)
                    Button("存为文件…") { saveFile() }
                        .bentoButton(plain: true)
                        .disabled(output.isEmpty)
                    Spacer()
                    Button {
                        app.pipe(output, to: PipelineTool.meta.id, from: memoryKey)
                    } label: {
                        HStack(spacing: 5) { Text("送入工具链"); Keycap(text: "⇥") }
                    }
                    .bentoButton(plain: true)
                    .disabled(output.isEmpty)
                    .help("把这个输出丢进工具链继续处理")
                }
            }
        }
    }

    // MARK: -

    private var status: StatusLine {
        if input.isEmpty {
            return StatusLine(level: .idle, text: idleText, trailing: trailing, trailingKey: "⌄")
        }
        if let error {
            return StatusLine(level: .error, text: error, trailing: trailing, trailingKey: "⌄")
        }
        return StatusLine(level: .ok, text: okText, trailing: trailing, trailingKey: "⌄")
    }

    private var inputMeta: String {
        "\(input.components(separatedBy: .newlines).count) 行 · \(input.count) 字符"
    }

    private var outputMeta: String {
        error == nil ? "\(output.count) 字符" : "—"
    }

    private func loadFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { onLoadFile?(url) }
    }

    private func saveFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "output.txt"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? output.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - 编解码方向

/// 编解码类工具共用的方向开关
enum ConvertDirection: Hashable {
    case encode, decode

    var toggled: ConvertDirection { self == .encode ? .decode : .encode }
    var okText: String { self == .encode ? "编码成功" : "解码成功" }
}

struct DirectionPicker: View {
    @Binding var direction: ConvertDirection
    var encodeLabel = "编码"
    var decodeLabel = "解码"

    var body: some View {
        BentoSegments(
            options: [(ConvertDirection.encode, encodeLabel), (.decode, decodeLabel)],
            selection: $direction, accent: true
        )
    }
}
