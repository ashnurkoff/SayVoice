import AppKit
import CoreGraphics

/// Inserts text through the pasteboard plus a synthetic Cmd+V.
/// Works in any application that supports Paste.
/// Used as the fallback when AXTextInjector cannot insert the text
/// (Chrome, Electron, Terminal and so on).
@MainActor
final class PasteboardInjector {

    private let kVKeyCode: CGKeyCode = 9   // virtual key code for 'v'

    /// The pause before the pasteboard is restored: the application has to read
    /// it on Cmd+V first. Restore any earlier and it pastes the previous
    /// contents instead of the dictation.
    private static let restoreDelay: Duration = .milliseconds(300)

    /// - Parameter restorePasteboard: put the previous pasteboard contents back
    ///   after the insertion. Off — the dictated text stays on the pasteboard
    ///   (Cmd+V repeats it), but whatever was there before is lost.
    func inject(text: String, restorePasteboard: Bool) {
        let pasteboard = NSPasteboard.general

        // A snapshot of the whole pasteboard. Only the string was saved before
        // (`string(forType: .string)`), so an image or a file on the pasteboard
        // was not restored at all — it simply disappeared.
        let saved = restorePasteboard ? snapshot(pasteboard) : []

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // Record the pasteboard "version" that carries our text: if it has
        // changed by the time we restore, somebody else has written to the
        // pasteboard and we must not overwrite them.
        let ourChangeCount = pasteboard.changeCount

        // A synchronous 20 ms pause, so the pasteboard update reaches every application
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

    /// A copy of every pasteboard item with every one of its representations.
    ///
    /// Promised data (file promises, lazily provided types) cannot be copied —
    /// `data(forType:)` returns nil for them, so those representations do not
    /// make it into the snapshot. For ordinary contents — text, images, file
    /// references, RTF — the snapshot is complete.
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
        // .privateState is a fully isolated source: it does not inherit the
        // physical key state. .hidSystemState inherits held keys (Option from
        // the hotkey, for one), which breaks Cmd+V in some applications.
        guard let source = CGEventSource(stateID: .privateState) else {
            print("[SayVoice] CGEventSource creation failed")
            return
        }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: kVKeyCode, keyDown: true)
        let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: kVKeyCode, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags   = .maskCommand

        keyDown?.post(tap: .cghidEventTap)

        // A 10 ms pause between keyDown and keyUp gives the application time to
        // handle the keyDown. Without it some applications miss the event.
        usleep(10_000)

        keyUp?.post(tap: .cghidEventTap)
    }
}
