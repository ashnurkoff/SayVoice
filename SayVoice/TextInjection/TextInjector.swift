import AppKit

/// Единая точка входа для инжекта текста.
/// Поддерживает два метода: Pasteboard (Cmd+V) и Accessibility API.
/// Метод выбирается через настройки (pasteMethod).
@MainActor
final class TextInjector {
    private let pasteboardInjector = PasteboardInjector()
    private let axInjector = AXTextInjector()

    /// Вставить text в активное текстовое поле фронтального приложения.
    /// - Parameters:
    ///   - text: текст для вставки
    ///   - method: "pasteboard" (Cmd+V, по умолчанию) или "ax" (Accessibility API с fallback на Pasteboard)
    ///   - restorePasteboard: вернуть прежнее содержимое буфера после вставки через Cmd+V
    func inject(text: String, method: String = "pasteboard", restorePasteboard: Bool = true) {
        guard !text.isEmpty else { return }

        // Trailing space для удобного продолжения набора
        let textWithSpace = text + " "

        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"

        // AX mode: попробовать Accessibility API, при неудаче — fallback на Pasteboard
        if method == "ax",
           let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            if axInjector.inject(text: textWithSpace, targetPID: pid) {
                print("[SayVoice] Text injected via AX → \(appName)")
                return
            }
            print("[SayVoice] AX failed for \(appName), falling back to Paste")
        }

        // Pasteboard mode (default) или AX fallback
        print("[SayVoice] Text injected via Paste → \(appName)")
        pasteboardInjector.inject(text: textWithSpace, restorePasteboard: restorePasteboard)
    }
}
