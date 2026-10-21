import AppKit
import Carbon.HIToolbox

/// A key plus Carbon modifier flags, stored in UserDefaults.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32   // Carbon: cmdKey, optionKey, controlKey, shiftKey

    static let `default` = Shortcut(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(controlKey | optionKey))

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Builds a combo from a key event; nil unless it holds ⌘, ⌥ or ⌃.
    init?(event: NSEvent) {
        let flags = event.modifierFlags
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        guard mods != 0 else { return nil }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        self.init(keyCode: UInt32(event.keyCode), modifiers: mods)
    }

    /// Glyphs for display, e.g. ["⌃", "⌥", "G"].
    var keys: [String] {
        var out: [String] = []
        if modifiers & UInt32(controlKey) != 0 { out.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { out.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { out.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { out.append("⌘") }
        out.append(Self.keyName(keyCode))
        return out
    }

    var display: String { keys.joined() }

    private static let special: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    private static func keyName(_ code: UInt32) -> String {
        if let name = special[Int(code)] { return name }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "?" }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var dead: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        data.withUnsafeBytes { buf in
            _ = UCKeyTranslate(buf.bindMemory(to: UCKeyboardLayout.self).baseAddress, UInt16(code),
                               UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                               OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &length, &chars)
        }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

/// A system-wide hotkey through Carbon's RegisterEventHotKey (no Accessibility permission needed).
final class GlobalShortcut {
    private var ref: EventHotKeyRef?
    private static var handlerInstalled = false
    private static var action: (() -> Void)?

    init(_ combo: Shortcut, action: @escaping () -> Void) {
        Self.action = action
        if !Self.handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { GlobalShortcut.action?() }
                return noErr
            }, 1, &spec, nil, nil)
            Self.handlerInstalled = true
        }
        let id = EventHotKeyID(signature: OSType(0x53_4C_4E_45), id: 1) // 'SLNE'
        RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }

    deinit { if let ref { UnregisterEventHotKey(ref) } }
}
