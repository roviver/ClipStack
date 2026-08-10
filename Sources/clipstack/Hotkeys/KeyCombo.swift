import AppKit
import Carbon.HIToolbox

/// Комбинация клавиш в терминах Carbon (именно он регистрирует глобальные хоткеи).
struct KeyCombo: Sendable, Codable, Equatable {
    var keyCode: UInt32
    /// Флаги Carbon (cmdKey, shiftKey, optionKey, controlKey), НЕ NSEvent.ModifierFlags —
    /// у них разные значения, и перепутать их легко.
    var carbonModifiers: UInt32

    static let defaultShow = KeyCombo(
        keyCode: UInt32(kVK_ANSI_V),
        carbonModifiers: UInt32(cmdKey | shiftKey)
    )

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    init(keyCode: UInt32, cocoaModifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        var carbon: Int = 0
        if cocoaModifiers.contains(.command) { carbon |= cmdKey }
        if cocoaModifiers.contains(.shift) { carbon |= shiftKey }
        if cocoaModifiers.contains(.option) { carbon |= optionKey }
        if cocoaModifiers.contains(.control) { carbon |= controlKey }
        self.carbonModifiers = UInt32(carbon)
    }

    /// Человекочитаемая запись вида «⇧⌘V» — для меню и экрана настроек.
    var displayString: String {
        var result = ""
        if carbonModifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        result += Self.keyName(for: keyCode)
        return result
    }

    private static func keyName(for keyCode: UInt32) -> String {
        // Раскладку не учитываем: имя клавиши берём по физической позиции, как это делает
        // сама macOS в меню — на кириллической раскладке ⇧⌘V всё равно показывается как V.
        let specials: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Escape: "⎋", kVK_Delete: "⌫",
            kVK_Tab: "⇥", kVK_LeftArrow: "←", kVK_RightArrow: "→",
            kVK_UpArrow: "↑", kVK_DownArrow: "↓"
        ]
        if let special = specials[Int(keyCode)] { return special }

        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "?"
        }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data

        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState, chars.count, &length, &chars
            )
        }
        guard status == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}
