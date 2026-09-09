import Carbon.HIToolbox
import CoreGraphics

/// The recording hotkey: a base key plus a set of modifiers.
///
/// There are two kinds, and the difference is not cosmetic — the kind decides
/// how the listener works:
///
/// * **A lone modifier** (right ⌥ and the like) — the press is caught when its
///   mask appears in `flagsChanged`. Such an event must not be consumed: an
///   eaten ⌥ would break typing special characters system-wide. The listener
///   stays an observer (`.listenOnly`), which means no input latency and no
///   risk of the tap being disabled on a timeout.
///
/// * **A regular key**, alone or with modifiers (⌥⌘D, F13) — caught on keyDown
///   and keyUp. It has to be consumed, or it would both start the recording and
///   type itself (or fire as somebody else's shortcut). Consuming is enabled
///   only for hotkeys of this kind.
///
/// * **A mouse button** (the side buttons, the middle one, the extra buttons of
///   gaming and productivity mice) — caught on `otherMouseDown`/`otherMouseUp`
///   by button number. Consumed as well: otherwise "Back" would keep paging
///   through the history during a dictation.
struct Hotkey: Equatable, Sendable {

    /// The code of the base key.
    let keyCode: CGKeyCode

    /// The raw `CGEventFlags` mask of the modifiers. For a lone modifier this is
    /// its own mask. Stored as `UInt64` rather than `CGEventFlags` so the type
    /// stays Sendable and can be read straight from the event tap callback.
    let flags: UInt64

    /// The mouse button number when the hotkey is assigned to the mouse; `nil`
    /// for a keyboard hotkey. Numbered as in CGEvent: 0 is left, 1 is right,
    /// 2 is middle, 3 and 4 are the side "Back" and "Forward" buttons, and the
    /// extra buttons follow.
    var mouseButton: Int?

    init(keyCode: CGKeyCode, flags: UInt64, mouseButton: Int? = nil) {
        self.keyCode = keyCode
        self.flags = flags
        self.mouseButton = mouseButton
    }

    /// A hotkey on a mouse button.
    init(mouseButton: Int) {
        self.keyCode = 0
        self.flags = 0
        self.mouseButton = mouseButton
    }

    /// The default hotkey — right Option: free in macOS and not used in typing.
    static let `default` = Hotkey(keyCode: 61, flags: CGEventFlags.maskAlternate.rawValue)

    var isMouse: Bool { mouseButton != nil }

    // MARK: - Kind of hotkey

    /// The codes of the modifier keys and the masks they raise.
    static let modifierKeys: [CGKeyCode: (mask: CGEventFlags, name: String)] = [
        61: (.maskAlternate,   "Right ⌥"),
        58: (.maskAlternate,   "Left ⌥"),
        54: (.maskCommand,     "Right ⌘"),
        55: (.maskCommand,     "Left ⌘"),
        62: (.maskControl,     "Right ⌃"),
        59: (.maskControl,     "Left ⌃"),
        60: (.maskShift,       "Right ⇧"),
        56: (.maskShift,       "Left ⇧"),
        63: (.maskSecondaryFn, "Fn"),
    ]

    /// The hotkey is a lone modifier: caught on `flagsChanged` and never consumed.
    var isModifierOnly: Bool { mouseButton == nil && Self.modifierKeys[keyCode] != nil }

    /// The events of this hotkey have to be eaten, so the key neither types
    /// itself nor fires as a shortcut of the active application.
    var requiresConsuming: Bool { !isModifierOnly }


    // MARK: - Display

    /// Labels for the mouse buttons. The numbers are the CGEvent ones.
    static func mouseButtonName(_ button: Int) -> String {
        switch button {
        case 2:  return "Middle mouse button"
        case 3:  return "Back mouse button"
        case 4:  return "Forward mouse button"
        default: return "Mouse button \(button + 1)"
        }
    }

    /// The label for the interface: "Right ⌥", "⌥⌘D", "F13", "Back mouse button".
    var displayName: String {
        if let button = mouseButton {
            return Self.mouseButtonName(button)
        }
        if let modifier = Self.modifierKeys[keyCode] {
            return modifier.name
        }
        return Self.modifierPrefix(flags) + Self.keyName(keyCode)
    }

    private static func modifierPrefix(_ flags: UInt64) -> String {
        let f = CGEventFlags(rawValue: flags)
        var s = ""
        if f.contains(.maskSecondaryFn) { s += "Fn" }
        if f.contains(.maskControl)     { s += "⌃" }
        if f.contains(.maskAlternate)   { s += "⌥" }
        if f.contains(.maskShift)       { s += "⇧" }
        if f.contains(.maskCommand)     { s += "⌘" }
        return s
    }

    /// Keys with no printable character — their names are fixed.
    private static let specialKeyNames: [CGKeyCode: String] = [
        36: "↩︎ Return", 48: "⇥ Tab", 49: "Space", 51: "⌫ Delete", 53: "⎋ Esc",
        76: "⌤ Enter", 117: "⌦ Fwd Delete",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19", 90: "F20",
    ]

    /// The name of a regular key.
    ///
    /// The character comes from the ASCII layout, not the active one: the hotkey
    /// is caught by key code and works in any layout, while a label taken from
    /// the active layout would jump around as the language is switched (⌥⌘D
    /// turning into its Cyrillic counterpart). macOS itself does the same when
    /// it shows shortcuts in a menu.
    static func keyName(_ keyCode: CGKeyCode) -> String {
        if let special = specialKeyNames[keyCode] { return special }
        if let char = printableCharacter(for: keyCode) { return char.uppercased() }
        return "Key \(keyCode)"
    }

    private static func printableCharacter(for keyCode: CGKeyCode) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPtr).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self)
            else { return nil }

            var deadKeyState: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDisplay), 0,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState, chars.count, &length, &chars
            )
            guard status == noErr, length > 0 else { return nil }
            let result = String(utf16CodeUnits: chars, count: length)
            return result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : result
        }
    }

    // MARK: - Validation

    enum Rejection {
        /// A printing key with no modifiers: consuming it would make the key
        /// useless in every application while SayVoice is running.
        case needsModifier
        /// A key that cannot meaningfully be held.
        case notUsable(String)

        var message: String {
            switch self {
            case .needsModifier:
                return "Add a modifier to a regular key — otherwise it stops typing in every app while SayVoice is running."
            case .notUsable(let reason):
                return reason
            }
        }
    }

    /// Checks whether a mouse button will do as the recording hotkey.
    static func validate(mouseButton: Int) -> Rejection? {
        // The left and right buttons are the basis of using the system;
        // consuming them would make the mouse useless while the app runs.
        if mouseButton <= 1 {
            return .notUsable("The left and right mouse buttons can't be assigned — without them you can't click or open context menus.")
        }
        return nil
    }

    /// Checks whether the pressed combination will do as the recording hotkey.
    static func validate(keyCode: CGKeyCode, flags: UInt64) -> Rejection? {
        if keyCode == 57 {
            return .notUsable("Caps Lock has no press/release pair, so holding it cannot work.")
        }
        // A lone modifier is always allowed.
        if modifierKeys[keyCode] != nil { return nil }

        let hasModifier = CGEventFlags(rawValue: flags)
            .intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn])
            .isEmpty == false
        if hasModifier { return nil }

        // Without modifiers, allow only keys that print nothing and are not
        // used for navigation — consuming those gets in nobody's way.
        let safeBare: Set<CGKeyCode> = [105, 107, 113, 106, 64, 79, 80, 90]  // F13–F20
        return safeBare.contains(keyCode) ? nil : .needsModifier
    }

    /// Known conflicts — the warning is shown in the settings, but the choice
    /// is not blocked.
    var warning: String? {
        if let button = mouseButton {
            if button == 2 {
                return "The middle button opens links in new tabs in many apps."
            }
            return "If Logi Options+ or a similar utility owns this button, the system never sees it — set the button to its default action."
        }
        switch keyCode {
        case 63:  return "Fn is used by macOS dictation."
        case 54:  return "Right ⌘ switches the keyboard layout for many users."
        case 56, 60: return "Holding ⇧ breaks typing capitals."
        case 58:  return "Left ⌥ is used for special characters."
        case 55:  return "Left ⌘ is part of almost every shortcut — awkward to hold."
        default:  return nil
        }
    }
}
