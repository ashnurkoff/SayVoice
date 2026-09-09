import SwiftUI

struct HotkeyStep: View {
    @Bindable var model: OnboardingModel
    var onHotkeyChanged: ((Hotkey) -> Void)?
    var onHotkeyModeChanged: ((Bool) -> Void)?

    var body: some View {
        // `settings` is a `let` reference to another observable object, so the
        // bindings the controls need are derived from a local `@Bindable`.
        @Bindable var settings = model.settings
        StepLayout(title: "Your hotkey",
                   subtitle: "Right ⌥ works out of the box. Change it here or later in Settings.") {
            Card {
                SettingsRow("Hotkey") {
                    HotkeyRecorder(hotkey: $settings.hotkey, onChange: onHotkeyChanged)
                }
                SettingsRow("Mode", note: settings.hotkeyIsToggle ? "Press once to start, again to stop." : "Recording runs while the key is held.") {
                    Picker("", selection: $settings.hotkeyMode) {
                        Text("Hold").tag("hold")
                        Text("Toggle").tag("toggle")
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 180)
                    .onChange(of: settings.hotkeyMode) { _, new in onHotkeyModeChanged?(new == "toggle") }
                }
            }
        } footer: {
            Button("Skip") { model.skip() }.buttonStyle(.dsLink)
            Button("Continue") { model.next() }.buttonStyle(.dsPrimary)
        }
    }
}
