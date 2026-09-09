import SwiftUI

/// Section title and subtitle on the left, the live status pill on the right.
struct SectionHeader: View {
    let section: SettingsSection
    let status: AppStatus

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: DS.Space.s16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(DS.font(.section))
                    .foregroundStyle(DS.Colors.text.color)
                Text(section.subtitle)
                    .font(DS.font(.body))
                    .foregroundStyle(DS.Colors.muted.color)
            }
            Spacer(minLength: DS.Space.s12)
            StatusPill(status: status)
        }
    }
}

/// "● Ready · Large Turbo Q5" — orb at 10 pt plus text, neutral capsule.
/// `compact` drops the model name for narrow hosts such as the popover header.
struct StatusPill: View {
    let status: AppStatus
    var compact: Bool = false

    var body: some View {
        HStack(spacing: DS.Space.s8) {
            Orb(state: status.orbState, size: 10)
            Text(compact ? status.compactText : status.pillText)
                .font(DS.font(.valueSmall))
                .foregroundStyle(DS.Colors.muted.color)
                // A pill that wraps reads as two broken lines, not as a label:
                // it keeps its one line and lets the header give way instead.
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.leading, 6)
        .padding(.trailing, DS.Space.s12)
        .padding(.vertical, 3)
        .background(Capsule().fill(DS.Colors.surface.color))
        .overlay(Capsule().strokeBorder(DS.Colors.line.color, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
