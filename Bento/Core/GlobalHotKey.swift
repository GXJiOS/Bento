import Foundation
import Carbon.HIToolbox
import AppKit

/// 全局热键。
///
/// 用 Carbon 的 `RegisterEventHotKey` —— 它是系统级注册，App 在后台也能收到，
/// 而且**不需要辅助功能权限**（`NSEvent.addGlobalMonitor` 那条路才需要）。
/// Carbon 的回调是 C 函数指针，捕获不了上下文，所以用一张全局表按 id 派发。
final class GlobalHotKey {

    struct Combo: Equatable, Hashable, Codable {
        var keyCode: UInt32
        var carbonModifiers: UInt32

        static let optionSpace = Combo(keyCode: UInt32(kVK_Space),
                                       carbonModifiers: UInt32(optionKey))
        static let commandShiftB = Combo(keyCode: UInt32(kVK_ANSI_B),
                                         carbonModifiers: UInt32(cmdKey | shiftKey))
        static let controlSpace = Combo(keyCode: UInt32(kVK_Space),
                                        carbonModifiers: UInt32(controlKey))

        var display: String {
            var s = ""
            if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
            if carbonModifiers & UInt32(optionKey) != 0 { s += "⌥" }
            if carbonModifiers & UInt32(shiftKey) != 0 { s += "⇧" }
            if carbonModifiers & UInt32(cmdKey) != 0 { s += "⌘" }
            s += Self.keyName(keyCode)
            return s
        }

        static func keyName(_ code: UInt32) -> String {
            switch Int(code) {
            case kVK_Space: return "Space"
            case kVK_ANSI_B: return "B"
            case kVK_ANSI_K: return "K"
            case kVK_ANSI_V: return "V"
            case kVK_Return: return "↩"
            default: return "Key\(code)"
            }
        }
    }

    // MARK: - 全局派发表

    private static var callbacks: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    private var ref: EventHotKeyRef?
    private let id: UInt32
    private(set) var combo: Combo

    /// 注册失败通常意味着这个组合已被系统或别的 App 占用
    init?(_ combo: Combo, action: @escaping () -> Void) {
        Self.installHandlerIfNeeded()
        self.combo = combo
        self.id = Self.nextID
        Self.nextID += 1

        let hotKeyID = EventHotKeyID(signature: OSType(0x424E_544F), id: id)  // 'BNTO'
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, ref != nil else { return nil }
        Self.callbacks[id] = action
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        Self.callbacks[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            GlobalHotKey.callbacks[hkID.id]?()
            return noErr
        }, 1, &spec, nil, nil)
    }
}
