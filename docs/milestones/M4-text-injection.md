# M4 — Text insertion

**Goal:** the transcribed text is inserted into the active text field automatically. A two-pronged strategy: AXUIElement (native applications) and the pasteboard + Cmd+V (everything else).

**Estimate:** 1-2 working days
**Dependencies:** M3 finished (TranscriptionEngine returns a String)
**Definition of done:** the test matrix passes — the text is inserted in TextEdit, Safari, Chrome, Xcode

---

## Tasks

### 1. AXTextInjector.swift

```swift
// SayVoice/TextInjection/AXTextInjector.swift
import AppKit
import ApplicationServices

/// Inserts text through the Accessibility API.
/// Puts the text at the caret, or replaces the selection.
final class AXTextInjector {

    /// Attempts an insertion through the AX API.
    /// - Returns: true on success, false when the fallback is needed
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

        guard result == .success, let focusedElement = focusedElementRef else {
            return false
        }

        let element = focusedElement as! AXUIElement

        // Step 2: check that this is a text field (not read-only)
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        // Even when AXValue is not settable, AXSelectedText may be available

        // Step 3: try AXSelectedText first — it respects the caret position
        if injectViaSelectedText(text: text, element: element) {
            return true
        }

        // Step 4: fallback — replace the whole AXValue (less desirable)
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
```

### 2. PasteboardInjector.swift

```swift
// SayVoice/TextInjection/PasteboardInjector.swift
import AppKit
import CoreGraphics

/// Inserts text through the pasteboard plus a synthetic Cmd+V.
/// Works in any application that supports Paste.
final class PasteboardInjector {

    private let kVKeyCode: CGKeyCode = 9   // virtual key code for 'v'

    func inject(text: String) {
        let pasteboard = NSPasteboard.general

        // Save the current contents of the pasteboard
        let savedString = pasteboard.string(forType: .string)
        let savedTypes = pasteboard.types ?? []

        // Write our text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // A short delay, so the pasteboard has time to update
        Thread.sleep(forTimeInterval: 0.02)

        // The synthetic Cmd+V
        sendCmdV()

        // Restore the pasteboard after 300 ms (enough for the Paste to finish)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let saved = savedString {
                pasteboard.clearContents()
                pasteboard.setString(saved, forType: .string)
            } else if !savedTypes.isEmpty {
                // The pasteboard held something other than a string — just clear it (binary data cannot be restored)
                // In production: save the whole NSPasteboardItem
            }
        }
    }

    private func sendCmdV() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: kVKeyCode, keyDown: true)
        let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: kVKeyCode, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags   = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
```

> **An improvement for production:** fully preserving the pasteboard means saving every `NSPasteboardItem` object, binary data (RTF, images) included. The basic implementation saves the string only.

### 3. TextInjector.swift

```swift
// SayVoice/TextInjection/TextInjector.swift
import AppKit

/// The single entry point for inserting text.
/// The strategy: AX (native applications) → the pasteboard (the universal fallback).
@MainActor
final class TextInjector {
    private let axInjector = AXTextInjector()
    private let pasteboardInjector = PasteboardInjector()

    /// Inserts text into the active text field of the frontmost application.
    func inject(text: String) {
        guard !text.isEmpty else { return }

        // A trailing space, so typing can continue straight after the insertion
        let textWithSpace = text + " "

        let frontApp = NSWorkspace.shared.frontmostApplication
        let pid = frontApp?.processIdentifier ?? 0

        if pid > 0 {
            let axSuccess = axInjector.inject(text: textWithSpace, targetPID: pid_t(pid))
            if axSuccess {
                return  // AX worked
            }
        }

        // Fallback: Pasteboard + Cmd+V
        pasteboardInjector.inject(text: textWithSpace)
    }
}
```

### 4. Wiring it into AppCoordinator (the M4 update)

```swift
// Add to AppCoordinator:
private let textInjector = TextInjector()

// Update handleKeyUp() — insert after the transcription:
func handleKeyUp() {
    guard state == .recording else { return }
    state = .transcribing

    Task {
        let samples = await audioRecorder.stopCapture()

        do {
            let text = try await transcriptionEngine.transcribe(samples)

            // Insert BEFORE the state changes — the active window is still ours
            state = .injecting
            overlayController?.show(message: text)
            textInjector.inject(text: text)

            // Save it to the history
            historyStore.append(TranscriptionEntry(
                id: UUID(),
                date: Date(),
                text: text,
                durationSeconds: Double(samples.count) / 16_000.0,
                language: nil
            ))

            // The overlay disappears after 1.5 sec
            overlayController?.dismiss(after: 1.5)
            state = .idle

        } catch TranscriptionError.recordingTooShort {
            state = .idle

        } catch TranscriptionError.emptyResult {
            overlayController?.show(message: "Didn't catch anything")
            overlayController?.dismiss(after: 2.0)
            state = .idle

        } catch TranscriptionError.modelNotLoaded {
            // Show the download screen
            state = .error(.modelNotLoaded)

        } catch {
            state = .error(.transcriptionFailed(error.localizedDescription))
        }
    }
}
```

---

## The test matrix

For every application check: press the hotkey → say a phrase → the text appears.

| Application | The expected strategy | The test |
|---|---|---|
| **TextEdit** (RTF) | AX — `kAXSelectedText` | Create a document, click into the text, record |
| **TextEdit** (Plain) | AX — `kAXSelectedText` | The same scenario |
| **Notes.app** | AX — `kAXSelectedText` | Create a note, click into it |
| **Xcode** (the editor) | AX — `kAXSelectedText` | Open a .swift file |
| **Safari** (the URL bar) | AX — `kAXSelectedText` | Click into the address bar |
| **Safari** (a text field) | AX or the pasteboard | Open any form |
| **Chrome** (a text field) | The pasteboard fallback | Open google.com, click the search box |
| **VS Code** (Electron) | The pasteboard fallback | Open any file |
| **Terminal** | The pasteboard fallback | Open the terminal |
| **Slack** (Electron) | The pasteboard fallback | Click into the message field |
| **Notion** (Electron) | The pasteboard fallback | Click into a page |
| **A password field** | Must NOT insert | Check in any login form |

### The test procedure for every application:
1. Switch to the application under test
2. Click into a text field (giving it focus and a caret)
3. Press Right Option, say "a test phrase", release
4. Check: the text has appeared in the field

---

## Known limitations

### Chrome / Electron applications
AX injection does not work (Chromium blocks `AXSelectedTextAttribute`). The pasteboard fallback works reliably. **This is normal and expected.**

### Password fields
macOS deliberately blocks both AX and synthetic events for password fields. SayVoice will not insert text into a password — **which is the right behaviour from a security point of view.** A message is shown in the overlay (optional).

### Remote Desktop / Screen Sharing
Synthetic CGEvents may not make it through to a remote session. This is a known limitation — not fixed in v1.

### Terminal applications
Terminal.app: the pasteboard + Cmd+V works. iTerm2: the same. For Terminal make sure the focus is in the window, not in the menu.

---

## Technical details

### The order in which the AX attributes are checked

```
1. kAXFocusedUIElementAttribute  → find the focused element
2. kAXSelectedTextAttribute      → try to insert at the caret (preferred)
   └─► isSettable? → no → fallback
3. kAXValueAttribute             → replace the whole value (if AXSelectedText is unavailable)
   └─► isSettable? → no → give up, hand over to the pasteboard
```

### Why AXSelectedText is preferable to AXValue

- `AXSelectedText` = insert at the caret, leaving the rest of the text alone
- `AXValue` = replace the entire contents of the field (losing the existing text unless the caret is at the end)

### Thread safety PasteboardInjector

`PasteboardInjector.inject()` is called on the `@MainActor`. `sendCmdV()` posts the events through `CGEventTapCreate` — which is safe from the main thread.

`Thread.sleep(0.02)` is a synchronous pause that guarantees the pasteboard is updated before Cmd+V is posted. Acceptable because it is called from the MainActor only during an active insertion (it does not block the UI permanently).

### Saving and restoring the pasteboard

A 300 ms delay is enough for most applications. Some (heavy Electron ones especially) may read the pasteboard slowly — in which case the text is already inserted by the time the pasteboard is restored.

---

## The M4 definition of done

- [x] TextEdit: the text is inserted at the caret — **AX via kAXSelectedText, works**
- [x] The Safari search bar: the text is inserted — **AX, works**
- [x] A Chrome input: the text is inserted through the pasteboard fallback — **Paste → Chrome, works**
- [x] Xcode: the text is inserted at the cursor — **AX, works**
- [x] The existing pasteboard contents are restored after the insertion — **after a 300 ms Task.sleep**
- [x] The overlay shows the transcribed text for 2.0 sec, then fades out — **2.0 sec (not the 1.5 of the plan)**
- [x] A password field: the text is NOT inserted (and nothing crashes) — **AX blocked + CGEvent blocked = correct**
- [x] An empty transcription: the overlay says "Didn't catch anything" and no insertion is attempted — **TranscriptionError.emptyResult**
- [x] The inserted text carries a trailing space, so typing can continue — **`text + " "`**

**Finished on: 2026-02-25**

---

## Implementation notes (differences from the plan)

1. **PasteboardInjector** — `@MainActor`; the pasteboard is restored through `Task { @MainActor in try? await Task.sleep(for: .seconds(0.3)) }` instead of `DispatchQueue.main.asyncAfter` (Swift 6 strict-concurrency safe).

2. **AXTextInjector** — `focusedRef as! AXUIElement` (a force cast after the `.success` check) instead of an `as?` conditional cast (the Clang error: "conditional downcast to CoreFoundation type always succeeds").

3. **Sublime Text, VS Code, Terminal** — the pasteboard fallback works correctly. The log: `Text injected via Paste → Sublime Text` (with no "failed").

4. **The overlay timeout** — 2.0 sec (not the 1.5 of the original plan). Long enough to read the transcription.

5. **historyStore** — not implemented (M5 scope). `AppCoordinator.handleKeyUp()` does not call `historyStore.append()`.

6. **The test phrases** — RU: a count from one to five plus "microphone check", spoken in Russian (p=0.987); EN: "1, 2, 3, 4, 5, check in, check in." (p=0.946); mixed: an English greeting followed by two Russian words and "testing 123" (p=0.690). All of them were inserted correctly into Sublime Text through the pasteboard.
