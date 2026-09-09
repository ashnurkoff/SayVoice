import SwiftUI

/// Terms the model should spell exactly as given, edited as chips.
struct DictionarySection: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Card(title: "Terms", subtitle: "Names and jargon the model should write exactly as given") {
            VStack(alignment: .leading, spacing: DS.Space.s8) {
                TagField(text: $settings.vocabularyPrompt, placeholder: "Add term")
                Text("Enter or comma adds a term, Backspace removes the last one. Terms are wrapped into a punctuated sentence before they reach the model, so they never change how it punctuates your speech. Empty = off.")
                    .font(DS.font(.caption))
                    .foregroundStyle(DS.Colors.muted.color)
            }
            .padding(.horizontal, DS.Space.s16)
            .padding(.top, DS.Space.s4)
        }
    }
}
