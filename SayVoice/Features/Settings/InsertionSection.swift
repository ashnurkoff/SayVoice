import SwiftUI

/// How the transcribed text reaches the active app: clipboard or accessibility.
struct InsertionSection: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Card(title: "Insertion") {
            SettingsRow("Method", note: methodNote) {
                Picker("", selection: $settings.pasteMethod) {
                    Text("Clipboard").tag("pasteboard")
                    Text("Accessibility").tag("ax")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }
            SettingsRow("Restore the clipboard after pasting", note: restoreNote) {
                Toggle("", isOn: $settings.restorePasteboard).labelsHidden().toggleStyle(.switch)
            }
        }
    }

    private var methodNote: String {
        settings.pasteMethod == "ax"
            ? "Writes straight into the focused field through the accessibility API; the clipboard is untouched. Works in native apps (TextEdit, Notes, Xcode, Safari). Chrome, Electron and Terminal do not expose it — there, insertion falls back to the clipboard."
            : "Puts the text on the clipboard and sends ⌘V. Works everywhere paste works."
    }

    private var restoreNote: String {
        settings.restorePasteboard
            ? "Whatever was on the clipboard — including images and files — is put back after pasting. ⌘V then pastes that, not the dictation; the last dictation is always in History."
            : "The dictated text stays on the clipboard so ⌘V repeats it. Whatever was there before is lost, including images and files."
    }
}
