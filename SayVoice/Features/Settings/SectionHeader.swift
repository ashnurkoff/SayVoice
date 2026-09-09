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

/// "● Ready · Large Turbo Q5" — a status dot plus text in a neutral capsule.
/// `compact` drops the model name for narrow hosts such as the popover header.
///
/// The dot is a status light coloured by `AppStatus.pillTint`, not the brand
/// orb: a pill is a readout, and green/red/amber says what the state is at a
/// glance. The orb keeps its accent idle where it is the brand mark.
struct StatusPill: View {
    static let dotSize: CGFloat = 8
    static let dotLeading: CGFloat = DS.Space.s8

    let status: AppStatus
    var compact: Bool = false

    var body: some View {
        HStack(spacing: DS.Space.s8) {
            Circle()
                .fill(status.pillTint.color)
                .frame(width: Self.dotSize, height: Self.dotSize)
                .animation(DS.Motion.stateChange, value: status.state)
            Text(compact ? status.compactText : status.pillText)
                .font(DS.font(.valueSmall))
                .foregroundStyle(DS.Colors.muted.color)
                // A pill that wraps reads as two broken lines, not as a label:
                // it keeps its one line and lets the header give way instead.
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.leading, Self.dotLeading)
        .padding(.trailing, DS.Space.s12)
        .padding(.vertical, 5)
        .background(Capsule().fill(DS.Colors.surface.color))
        .overlay(Capsule().strokeBorder(DS.Colors.line.color, lineWidth: 1))
        .accessibilityElement(children: .combine)
        // The compact pill drops the model name on screen, never for VoiceOver.
        .accessibilityLabel(status.pillText)
    }
}
