import AppKit
import ApplicationServices

/// Inserts text through the Accessibility API.
/// Puts the text at the caret, or replaces the selection.
/// Works in native Cocoa applications (TextEdit, Notes, Xcode, Safari).
/// Chrome and Electron block AX — that is expected, and PasteboardInjector is used instead.
final class AXTextInjector {

    /// Attempts an insertion through the AX API.
    /// - Returns: true on success, false when the pasteboard fallback is needed
    func inject(text: String, targetPID: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(targetPID)
        return injectIntoApp(text: text, appElement: app)
    }

    private func injectIntoApp(text: String, appElement: AXUIElement) -> Bool {
        // Step 1: get the focused element
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

        // Step 2: try AXSelectedText first — it respects the caret position
        if injectViaSelectedText(text: text, element: element) {
            return true
        }

        // Step 3: fallback — replace the whole AXValue (less desirable)
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        if settable.boolValue {
            return injectViaFullValue(text: text, element: element)
        }

        return false
    }

    /// Inserts the text at the current caret position, replacing the selection if there is one.
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

    /// Appends the text to the field's current value (the fallback for AXSelectedText).
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
