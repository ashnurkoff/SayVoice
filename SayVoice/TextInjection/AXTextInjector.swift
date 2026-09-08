import AppKit
import ApplicationServices

/// Инжект текста через Accessibility API.
/// Вставляет текст в позицию каретки или заменяет выделение.
/// Работает в нативных Cocoa-приложениях (TextEdit, Notes, Xcode, Safari).
/// Chrome/Electron блокируют AX — это ожидаемо, используется PasteboardInjector.
final class AXTextInjector {

    /// Попытка инжекта через AX API.
    /// - Returns: true если успешно, false если нужен pasteboard fallback
    func inject(text: String, targetPID: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(targetPID)
        return injectIntoApp(text: text, appElement: app)
    }

    private func injectIntoApp(text: String, appElement: AXUIElement) -> Bool {
        // Шаг 1: Получить сфокусированный элемент
        var focusedElementRef: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )

        guard result == .success, let focusedRef = focusedElementRef else {
            return false
        }

        let element = focusedRef as! AXUIElement

        // Шаг 2: Попытаться вставить через AXSelectedText (предпочтительно — уважает позицию каретки)
        if injectViaSelectedText(text: text, element: element) {
            return true
        }

        // Шаг 3: Fallback — заменить весь AXValue (менее предпочтительно)
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        if settable.boolValue {
            return injectViaFullValue(text: text, element: element)
        }

        return false
    }

    /// Вставляет текст в текущую позицию каретки, заменяя выделение если есть.
    private func injectViaSelectedText(text: String, element: AXUIElement) -> Bool {
        var isSettable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &isSettable)
        guard isSettable.boolValue else { return false }

        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        )
        return result == .success
    }

    /// Добавляет текст к текущему значению поля (fallback для AXSelectedText).
    private func injectViaFullValue(text: String, element: AXUIElement) -> Bool {
        var currentValueRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &currentValueRef)
        let existing = (currentValueRef as? String) ?? ""

        let result = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            (existing + text) as CFString
        )
        return result == .success
    }
}
