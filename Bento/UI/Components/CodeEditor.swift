import SwiftUI
import AppKit

/// 等宽文本区 —— 包一层 NSTextView（TextKit 2）。
///
/// 唯一值得前期投资的自研组件：Phase 2 之后几乎每个工具都用它。
/// 关键点是去掉 NSTextView 自带的边框和背景，让**卡片**去表达边界和焦点环。
struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool = true
    /// 需要高亮的区间（正则测试器这类用）
    var highlights: [NSRange] = []

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.delegate = context.coordinator
        tv.drawsBackground = false
        tv.isRichText = false
        tv.isEditable = isEditable
        tv.isSelectable = true
        tv.allowsUndo = true
        tv.usesFindBar = true
        // 工具类输入必须关掉这些「智能」替换，否则引号和连字符会被改写
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.textContainerInset = NSSize(width: 0, height: 4)
        tv.textContainer?.lineFragmentPadding = 0
        tv.typingAttributes = Self.baseAttributes

        context.coordinator.textView = tv
        tv.string = text
        applyStyle(to: tv)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self

        if tv.string != text {
            let sel = tv.selectedRange()
            tv.string = text
            // 外部改写文本（比如 ⇅ 交换）后尽量保住光标位置
            if sel.location <= (text as NSString).length {
                tv.setSelectedRange(NSRange(location: min(sel.location, (text as NSString).length),
                                            length: 0))
            }
        }
        tv.isEditable = isEditable
        applyStyle(to: tv)
    }

    // MARK: - 排版

    static var baseAttributes: [NSAttributedString.Key: Any] {
        let ps = NSMutableParagraphStyle()
        ps.lineHeightMultiple = 1.5
        return [
            .font: Tokens.nsMono,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: ps,
        ]
    }

    private func applyStyle(to tv: NSTextView) {
        guard let storage = tv.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes(Self.baseAttributes, range: full)
        if !highlights.isEmpty {
            let bg = NSColor.controlAccentColor.withAlphaComponent(0.26)
            for r in highlights where NSMaxRange(r) <= storage.length {
                storage.addAttribute(.backgroundColor, value: bg, range: r)
            }
        }
        storage.endEditing()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        weak var textView: NSTextView?

        init(_ parent: CodeEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}

/// 带空状态提示的等宽区域。空状态给灰色示例值，别留白页。
struct CodeArea: View {
    @Binding var text: String
    var isEditable: Bool = true
    var placeholder: String = ""
    var highlights: [NSRange] = []

    var body: some View {
        CodeEditor(text: $text, isEditable: isEditable, highlights: highlights)
            .overlay(alignment: .topLeading) {
                if text.isEmpty && !placeholder.isEmpty {
                    Text(placeholder)
                        .font(Tokens.mono)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, Tokens.padCard)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
