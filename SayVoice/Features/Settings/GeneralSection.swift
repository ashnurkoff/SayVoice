import SwiftUI

/// Hotkey card (recorder + Hold/Toggle) and the recording-behaviour card.
struct GeneralSection: View {
    @Bindable var settings: SettingsStore
    var onHotkeyChanged: ((Hotkey) -> Void)?
    var onHotkeyModeChanged: ((Bool) -> Void)?

    var body: some View {
        VStack(spacing: DS.Space.s16) {
            Card(title: "Recording hotkey", subtitle: "A key, a combination or a mouse button") {
                SettingsRow("Hotkey") {
                    HotkeyRecorder(hotkey: $settings.hotkey, onChange: onHotkeyChanged)
                }
                SettingsRow("Mode", note: modeNote) {
                    Picker("", selection: $settings.hotkeyMode) {
                        Text("Hold").tag("hold")
                        Text("Toggle").tag("toggle")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 180)
                    .onChange(of: settings.hotkeyMode) { _, new in onHotkeyModeChanged?(new == "toggle") }
                }
            }

            Card(title: "While recording") {
                SettingsRow("Show the overlay", note: "Glass capsule near the bottom of the screen") {
                    Toggle("", isOn: $settings.overlayEnabled).labelsHidden().toggleStyle(.switch)
                }
                SettingsRow("Sound feedback", note: "A short tone when recording starts and stops") {
                    Toggle("", isOn: $settings.soundFeedback).labelsHidden().toggleStyle(.switch)
                }
            }
        }
    }

    private var modeNote: String {
        settings.hotkeyIsToggle
            ? "Press once to start, again to stop. Needed for buttons that do not report being held, such as those remapped in Logi Options+."
            : "Recording runs while the key or button is held."
    }
}
