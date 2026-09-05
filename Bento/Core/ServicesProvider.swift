import Foundation
import AppKit

/// Services 菜单的处理端。方法名要和 Info.plist 里的 `NSMessage` 对上，
/// 签名必须是这个固定形状，否则系统找不到。
///
/// 返回值写回 pasteboard 后，在支持编辑的地方会**原地替换选中文本**。
final class ServicesProvider: NSObject {

    // MARK: - 通用管道

    private func transform(_ pboard: NSPasteboard,
                           _ error: AutoreleasingUnsafeMutablePointer<NSString>,
                           _ body: (String) -> String?) {
        guard let input = pboard.string(forType: .string) else {
            error.pointee = "没有取到文本" as NSString
            return
        }
        guard let output = body(input) else {
            error.pointee = "无法处理这段内容" as NSString
            return
        }
        pboard.clearContents()
        pboard.setString(output, forType: .string)
    }

    // MARK: - 具体动作

    /// 识别内容类型后跳到对应工具，并把文本带过去
    @objc func bentoDetect(_ pboard: NSPasteboard, userData: String?,
                           error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let input = pboard.string(forType: .string) else {
            error.pointee = "没有取到文本" as NSString
            return
        }
        let state = AppState.shared
        if let hit = ContentDetector.detect(input),
           let name = hit.relatedToolNames.first,
           let item = ToolRegistry.items.first(where: { $0.name == name }), item.implemented {
            state.pipe(input, to: item.id, from: "Services 菜单")
        } else {
            state.pendingInput = input
            state.paletteQuery = input
        }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }

    @objc func bentoFormatJSON(_ pboard: NSPasteboard, userData: String?,
                               error: AutoreleasingUnsafeMutablePointer<NSString>) {
        transform(pboard, error) { input in
            guard let data = input.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data,
                                                              options: [.fragmentsAllowed]),
                  let out = try? JSONSerialization.data(
                    withJSONObject: obj,
                    options: [.prettyPrinted, .withoutEscapingSlashes, .fragmentsAllowed])
            else { return nil }
            return String(data: out, encoding: .utf8)
        }
    }

    @objc func bentoBase64Encode(_ pboard: NSPasteboard, userData: String?,
                                 error: AutoreleasingUnsafeMutablePointer<NSString>) {
        transform(pboard, error) { Data($0.utf8).base64EncodedString() }
    }

    @objc func bentoBase64Decode(_ pboard: NSPasteboard, userData: String?,
                                 error: AutoreleasingUnsafeMutablePointer<NSString>) {
        transform(pboard, error) { input in
            var t = input.filter { !$0.isWhitespace }
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            t += String(repeating: "=", count: (4 - t.count % 4) % 4)
            guard let d = Data(base64Encoded: t, options: [.ignoreUnknownCharacters]) else {
                return nil
            }
            return String(data: d, encoding: .utf8)
        }
    }

    @objc func bentoURLDecode(_ pboard: NSPasteboard, userData: String?,
                              error: AutoreleasingUnsafeMutablePointer<NSString>) {
        transform(pboard, error) { $0.removingPercentEncoding }
    }
}
