import SwiftUI

/// The closing step: a success mark, one sentence naming the hotkey the user
/// ends up with, and the button that starts the app.
struct DoneStep: View {
    let model: OnboardingModel

    /// Read from settings rather than written into the copy: the previous step
    /// may just have changed the hotkey, and the sentence has to say so.
    var message: String {
        "Hold \(model.settings.hotkey.displayName) and speak — the text lands where your cursor is."
    }

    var body: some View {
        StepLayout(title: "You're all set", subtitle: message, centersContent: true) {
            HStack {
                Spacer(minLength: 0)
                // The one moment the app celebrates anything: the mark draws
                // itself in, and at 72 pt it is the thing the eye lands on.
                Orb(state: .done, size: 72)
                Spacer(minLength: 0)
            }
            .padding(.top, DS.Space.s20)
        } footer: {
            // No skip: there is nothing left to decide.
            Button("Start") { model.next() }.buttonStyle(.dsPrimary)
        }
    }
}
