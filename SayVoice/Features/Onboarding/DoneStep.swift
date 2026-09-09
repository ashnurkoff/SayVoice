import SwiftUI

/// The closing step: a success mark, one sentence naming the hotkey the user
/// ends up with, and the button that starts the app. The only step laid out as
/// a centred column — mark, title, sentence — with Start still bottom-right.
struct DoneStep: View {
    let model: OnboardingModel

    /// Read from settings rather than written into the copy: the previous step
    /// may just have changed the hotkey, and the sentence has to say so.
    var message: String {
        "Hold \(model.settings.hotkey.displayName) and speak — the text lands where your cursor is."
    }

    var body: some View {
        StepLayout(title: "You're all set", subtitle: message,
                   centersContent: true, alignment: .center, contentLeadsTitle: true) {
            // The one moment the app celebrates anything: the mark draws itself
            // in, and at 72 pt above the title it is the thing the eye lands on.
            Orb(state: .done, size: 72)
                .padding(.bottom, DS.Space.s8)
        } footer: {
            // No skip: there is nothing left to decide.
            Button("Start") { model.next() }.buttonStyle(.dsPrimary)
        }
    }
}
