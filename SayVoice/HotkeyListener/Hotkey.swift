import Carbon.HIToolbox
import CoreGraphics

/// Хоткей записи: базовая клавиша плюс набор модификаторов.
///
/// Различаются два вида, и это не косметика — от вида зависит режим работы слушателя:
///
/// * **Модификатор-одиночка** (правый ⌥ и т.п.) — нажатие ловится по появлению его
///   маски в `flagsChanged`. Такое событие перехватывать нельзя: съеденный ⌥ сломал бы
///   набор спецсимволов во всей системе. Слушатель остаётся наблюдателем (`.listenOnly`),
///   то есть без задержки ввода и без риска отключения tap'а по таймауту.
///
/// * **Обычная клавиша**, одна или с модификаторами (⌥⌘D, F13) — ловится по keyDown и
///   keyUp. Её приходится перехватывать, иначе она и запустит запись, и напечатается
///   (или сработает как чужой шорткат). Перехват включается только для таких хоткеев.
///
/// * **Кнопка мыши** (боковые кнопки, средняя, дополнительные кнопки игровых и
///   продуктивных мышей) — ловится по `otherMouseDown`/`otherMouseUp` с номером кнопки.
///   Тоже перехватывается: иначе «Назад» продолжит листать страницы во время диктовки.
struct Hotkey: Equatable, Sendable {

    /// Код базовой клавиши.
    let keyCode: CGKeyCode

    /// Сырая маска `CGEventFlags` модификаторов. Для модификатора-одиночки — маска
    /// его самого. Хранится `UInt64`, а не `CGEventFlags`, чтобы тип оставался Sendable
    /// и читался прямо из колбэка event tap'а.
    let flags: UInt64

    /// Номер кнопки мыши, если хоткей назначен на мышь. `nil` — хоткей клавиатурный.
    /// Нумерация как в CGEvent: 0 — левая, 1 — правая, 2 — средняя, 3 и 4 — боковые
    /// «Назад» и «Вперёд», дальше — дополнительные кнопки.
    var mouseButton: Int?

    init(keyCode: CGKeyCode, flags: UInt64, mouseButton: Int? = nil) {
        self.keyCode = keyCode
        self.flags = flags
        self.mouseButton = mouseButton
    }

    /// Хоткей на кнопке мыши.
    init(mouseButton: Int) {
        self.keyCode = 0
        self.flags = 0
        self.mouseButton = mouseButton
    }

    /// Хоткей по умолчанию — правый Option: свободен в macOS и не участвует в наборе.
    static let `default` = Hotkey(keyCode: 61, flags: CGEventFlags.maskAlternate.rawValue)

    var isMouse: Bool { mouseButton != nil }

    // MARK: - Вид хоткея

    /// Коды клавиш-модификаторов и маски, которые они поднимают.
    static let modifierKeys: [CGKeyCode: (mask: CGEventFlags, name: String)] = [
        61: (.maskAlternate,   "Правый ⌥"),
        58: (.maskAlternate,   "Левый ⌥"),
        54: (.maskCommand,     "Правый ⌘"),
        55: (.maskCommand,     "Левый ⌘"),
        62: (.maskControl,     "Правый ⌃"),
        59: (.maskControl,     "Левый ⌃"),
        60: (.maskShift,       "Правый ⇧"),
        56: (.maskShift,       "Левый ⇧"),
        63: (.maskSecondaryFn, "Fn"),
    ]

    /// Хоткей — одиночный модификатор, ловится по `flagsChanged` и не перехватывается.
    var isModifierOnly: Bool { mouseButton == nil && Self.modifierKeys[keyCode] != nil }

    /// События этого хоткея нужно съедать, чтобы клавиша не печаталась
    /// и не срабатывала как шорткат активного приложения.
    var requiresConsuming: Bool { !isModifierOnly }


    // MARK: - Отображение

    /// Подписи кнопок мыши. Номера — как в CGEvent.
    static func mouseButtonName(_ button: Int) -> String {
        switch button {
        case 2:  return "Средняя кнопка мыши"
        case 3:  return "Кнопка мыши «Назад»"
        case 4:  return "Кнопка мыши «Вперёд»"
        default: return "Кнопка мыши \(button + 1)"
        }
    }

    /// Подпись для интерфейса: «Правый ⌥», «⌥⌘D», «F13», «Кнопка мыши «Назад»».
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

    /// Клавиши без печатного символа — у них имя фиксированное.
    private static let specialKeyNames: [CGKeyCode: String] = [
        36: "↩︎ Return", 48: "⇥ Tab", 49: "Пробел", 51: "⌫ Delete", 53: "⎋ Esc",
        76: "⌤ Enter", 117: "⌦ Fwd Delete",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19", 90: "F20",
    ]

    /// Имя обычной клавиши.
    ///
    /// Символ берётся из ASCII-раскладки, а не из активной: хоткей ловится по коду
    /// клавиши и работает в любой раскладке, а вот подпись, взятая из активной, прыгала
    /// бы при переключении языка (⌥⌘D превращалось в ⌥⌘В). Так же поступает сама macOS,
    /// показывая сочетания в меню.
    static func keyName(_ keyCode: CGKeyCode) -> String {
        if let special = specialKeyNames[keyCode] { return special }
        if let char = printableCharacter(for: keyCode) { return char.uppercased() }
        return "Клавиша \(keyCode)"
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

    // MARK: - Проверка допустимости

    enum Rejection {
        /// Печатная клавиша без модификаторов: перехват сделал бы её нерабочей
        /// во всех приложениях, пока SayVoice запущен.
        case needsModifier
        /// Клавиша, которую нельзя удерживать осмысленно.
        case notUsable(String)

        var message: String {
            switch self {
            case .needsModifier:
                return "К обычной клавише добавь модификатор — иначе она перестанет печататься во всех приложениях, пока SayVoice запущен."
            case .notUsable(let reason):
                return reason
            }
        }
    }

    /// Проверяет, годится ли кнопка мыши как хоткей записи.
    static func validate(mouseButton: Int) -> Rejection? {
        // Левая и правая кнопки — основа работы с системой; их перехват сделал бы
        // мышь бесполезной, пока приложение запущено.
        if mouseButton <= 1 {
            return .notUsable("Левую и правую кнопки мыши назначить нельзя — без них не выйдет ни кликнуть, ни вызвать контекстное меню.")
        }
        return nil
    }

    /// Проверяет, годится ли нажатая комбинация как хоткей записи.
    static func validate(keyCode: CGKeyCode, flags: UInt64) -> Rejection? {
        if keyCode == 57 {
            return .notUsable("Caps Lock не даёт пары «нажатие — отпускание», удержание с ним не работает.")
        }
        // Модификатор-одиночка допустим всегда.
        if modifierKeys[keyCode] != nil { return nil }

        let hasModifier = CGEventFlags(rawValue: flags)
            .intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn])
            .isEmpty == false
        if hasModifier { return nil }

        // Без модификаторов разрешаем только клавиши, которые ничего не печатают
        // и не используются в навигации — их перехват никому не мешает.
        let safeBare: Set<CGKeyCode> = [105, 107, 113, 106, 64, 79, 80, 90]  // F13–F20
        return safeBare.contains(keyCode) ? nil : .needsModifier
    }

    /// Известные конфликты — предупреждение показывается в настройках,
    /// но выбор не блокируется.
    var warning: String? {
        if let button = mouseButton {
            if button == 2 {
                return "Средняя кнопка у многих открывает ссылки в новой вкладке."
            }
            return "Если кнопке назначено действие в Logi Options+ или похожей утилите, система её не увидит — переведите кнопку в состояние по умолчанию."
        }
        switch keyCode {
        case 63:  return "Fn занята системной диктовкой macOS."
        case 54:  return "Правый ⌘ у многих переключает раскладку клавиатуры."
        case 56, 60: return "Удержание ⇧ ломает набор заглавных."
        case 58:  return "Левый ⌥ используется для ввода спецсимволов."
        case 55:  return "Левый ⌘ участвует почти во всех сочетаниях — удерживать неудобно."
        default:  return nil
        }
    }
}
