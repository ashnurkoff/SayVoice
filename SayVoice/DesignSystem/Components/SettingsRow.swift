import SwiftUI

/// One settings line: label (and optional note) on the left, control on the
/// right, 44pt tall, hairline on top. Notes are `caption`/`muted` — the only
/// place explanatory text is allowed inside a card.
struct SettingsRow<Control: View>: View {
    let label: String
    let note: String?
    @ViewBuilder let control: () -> Control

    init(_ label: String, note: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.label = label
        self.note = note
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.s12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(DS.font(.bodyMedium)).foregroundStyle(DS.Colors.text.color)
                if let note { Text(note).font(DS.font(.caption)).foregroundStyle(DS.Colors.muted.color) }
            }
            Spacer(minLength: DS.Space.s12)
            // The label rides on the control rather than on the row, so a
            // segmented or menu picker keeps a VoiceOver element per option.
            Group { control() }
                .accessibilityLabel(label)
        }
        .padding(.horizontal, DS.Space.s16)
        .frame(minHeight: DS.Size.settingsRow)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.Colors.line.color).frame(height: 1).padding(.leading, DS.Space.s16)
        }
        // A container, not one merged element: a toggle still announces the
        // label it belongs to (the control carries it), while the options of a
        // picker stay reachable one by one — merging swallowed them.
        .accessibilityElement(children: .contain)
    }
}
