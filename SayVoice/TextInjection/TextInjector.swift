import AppKit

/// The single entry point for inserting text.
/// Supports two methods: the pasteboard (Cmd+V) and the Accessibility API.
/// The method is chosen in the settings (pasteMethod).
@MainActor
final class TextInjector {
    private let pasteboardInjector = PasteboardInjector()
    private let axInjector = AXTextInjector()

    /// Inserts text into the active text field of the frontmost application.
    /// - Parameters:
    ///   - text: the text to insert
    ///   - method: "pasteboard" (Cmd+V, the default) or "ax" (Accessibility API, falling back to the pasteboard)
    ///   - restorePasteboard: put the previous clipboard contents back after a Cmd+V insertion
    func inject(text: String, method: String = "pasteboard", restorePasteboard: Bool = true) {
        guard !text.isEmpty else { return }

        // A trailing space, so typing can continue straight after the insertion
        let textWithSpace = text + " "

        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"

        // AX mode: try the Accessibility API, and fall back to the pasteboard on failure
        if method == "ax",
           let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            if axInjector.inject(text: textWithSpace, targetPID: pid) {
                print("[SayVoice] Text injected via AX → \(appName)")
                return
            }
            print("[SayVoice] AX failed for \(appName), falling back to Paste")
        }

        // Pasteboard mode (the default), or the AX fallback
        print("[SayVoice] Text injected via Paste → \(appName)")
        pasteboardInjector.inject(text: textWithSpace, restorePasteboard: restorePasteboard)
    }
}
