import AppKit
import CoreGraphics

/// Инжект текста через буфер обмена + синтетический Cmd+V.
/// Работает в любом приложении, которое поддерживает Paste.
/// Используется как fallback когда AXTextInjector не может вставить текст
/// (Chrome, Electron, Terminal и т.д.).
@MainActor
final class PasteboardInjector {

    private let kVKeyCode: CGKeyCode = 9   // virtual key code для 'v'

    /// Пауза перед возвратом буфера: приложение должно успеть прочитать буфер по Cmd+V.
    /// Вернём раньше — вставится прежнее содержимое вместо диктовки.
    private static let restoreDelay: Duration = .milliseconds(300)

    /// - Parameter restorePasteboard: вернуть прежнее содержимое буфера после вставки.
    ///   Выключено — в буфере остаётся продиктованный текст (Cmd+V его повторяет),
    ///   но то, что лежало в буфере раньше, теряется.
    func inject(text: String, restorePasteboard: Bool) {
        let pasteboard = NSPasteboard.general

        // Снимок буфера целиком. Раньше сохранялась только строка
        // (`string(forType: .string)`), поэтому изображение или файл в буфере
        // не восстанавливались вовсе — просто пропадали.
        let saved = restorePasteboard ? snapshot(pasteboard) : []

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // Фиксируем «версию» буфера с нашим текстом: если к моменту возврата она
        // изменилась, значит буфер перезаписал кто-то ещё — не затираем его.
        let ourChangeCount = pasteboard.changeCount

        // Синхронная пауза 20ms чтобы буфер успел обновиться для всех приложений
        Thread.sleep(forTimeInterval: 0.02)

        sendCmdV()

        guard restorePasteboard, !saved.isEmpty else { return }

        Task { @MainActor in
            try? await Task.sleep(for: Self.restoreDelay)
            guard pasteboard.changeCount == ourChangeCount else { return }
            pasteboard.clearContents()
            pasteboard.writeObjects(saved)
        }
    }

    // MARK: - Private

    /// Копия всех элементов буфера со всеми их представлениями.
    ///
    /// Отложенные данные (file promises, лениво предоставляемые типы) скопировать
    /// нельзя — `data(forType:)` для них возвращает nil, такие представления
    /// в снимок не попадут. Для обычного содержимого — текста, изображений,
    /// файловых ссылок, RTF — снимок полный.
    private func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.compactMap { item in
            let copy = NSPasteboardItem()
            var hasData = false
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                    hasData = true
                }
            }
            return hasData ? copy : nil
        }
    }

    private func sendCmdV() {
        // .privateState — полностью изолированный источник, не наследует
        // физическое состояние клавиш. .hidSystemState наследует зажатые клавиши
        // (напр. Option от hotkey), что ломает Cmd+V в некоторых приложениях.
        guard let source = CGEventSource(stateID: .privateState) else {
            print("[SayVoice] CGEventSource creation failed")
            return
        }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: kVKeyCode, keyDown: true)
        let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: kVKeyCode, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags   = .maskCommand

        keyDown?.post(tap: .cghidEventTap)

        // Пауза 10ms между keyDown и keyUp — даёт приложению время обработать keyDown.
        // Без паузы некоторые приложения пропускают событие.
        usleep(10_000)

        keyUp?.post(tap: .cghidEventTap)
    }
}
