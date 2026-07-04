import AppKit
import Carbon.HIToolbox

/// A user-configurable global hotkey (Carbon key code + modifier flags).
struct Hotkey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32  // Carbon modifier mask (cmdKey, shiftKey, optionKey, controlKey)

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard !flags.isEmpty else { return nil }
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        self.init(keyCode: UInt32(event.keyCode), modifiers: carbon)
    }

    var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        s += Hotkey.keyName(for: keyCode)
        return s
    }

    /// Modifier mask for NSMenuItem.keyEquivalentModifierMask.
    var nsModifierMask: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }

    /// Single-character key equivalent for NSMenuItem (letters/digits only).
    var menuKeyEquivalent: String {
        let digits: [UInt32: String] = [
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
        ]
        if let digit = digits[keyCode] { return digit }
        let name = Hotkey.keyName(for: keyCode)
        return name.count == 1 ? name.lowercased() : ""
    }

    /// True when this combo can be registered with Carbon (has modifiers, not system-reserved).
    var isValid: Bool {
        guard modifiers != 0 else { return false }
        if Self.isReserved(self) { return false }
        return true
    }

    /// Human-readable reason this hotkey is rejected.
    var invalidReason: String? {
        if modifiers == 0 { return "Must include ⌘, ⌥, ⌃, or ⇧" }
        if Self.isReserved(self) { return "Reserved by macOS (\(displayString))" }
        return nil
    }

    /// System-reserved combos that macOS won't release even if disabled in Settings.
    static func isReserved(_ hotkey: Hotkey) -> Bool {
        // Built-in screenshot shortcuts ⇧⌘3/4/5 (only if still enabled in macOS).
        let shiftCmd = UInt32(cmdKey | shiftKey)
        if hotkey.modifiers == shiftCmd && [UInt32(kVK_ANSI_3), UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5)].contains(hotkey.keyCode) {
            return true
        }
        return false
    }

    static func keyName(for keyCode: UInt32) -> String {
        let special: [UInt32: String] = [
            UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥", UInt32(kVK_Space): "Space",
            UInt32(kVK_Delete): "⌫", UInt32(kVK_Escape): "⎋",
            UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
            UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
            UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        ]
        if let name = special[keyCode] { return name }
        // Translate via the current keyboard layout.
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "Key\(keyCode)"
        }
        let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> OSStatus in
            let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress!
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "Key\(keyCode)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

enum HotkeyAction: String, Codable, CaseIterable, Identifiable {
    case captureArea, captureWindow, captureScreen, captureScrolling, showHistory

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .captureArea: return "Capture Area"
        case .captureWindow: return "Capture Window"
        case .captureScreen: return "Capture Full Screen"
        case .captureScrolling: return "Scrolling Capture"
        case .showHistory: return "Show History"
        }
    }

    /// Defaults avoid the system's ⇧⌘3/4/5 and common ⇧⌘1/2 conflicts.
    var defaultHotkey: Hotkey {
        let mods = UInt32(controlKey | optionKey)
        switch self {
        case .captureArea: return Hotkey(keyCode: UInt32(kVK_ANSI_1), modifiers: mods)
        case .captureWindow: return Hotkey(keyCode: UInt32(kVK_ANSI_2), modifiers: mods)
        case .captureScreen: return Hotkey(keyCode: UInt32(kVK_ANSI_6), modifiers: mods)
        case .captureScrolling: return Hotkey(keyCode: UInt32(kVK_ANSI_8), modifiers: mods)
        case .showHistory: return Hotkey(keyCode: UInt32(kVK_ANSI_9), modifiers: mods)
        }
    }
}
