import SwiftUI

/// One settings line: label (and optional note) on the left, control on the
/// right, at least 44 pt tall, hairline on top. Notes are `caption`/`muted` —
/// the only place explanatory text is allowed inside a card.
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
        SettingsRowLayout(spacing: DS.Space.s12) {
            Text(label).font(DS.font(.bodyMedium)).foregroundStyle(DS.Colors.text.color)
            if let note {
                Text(note).font(DS.font(.caption)).foregroundStyle(DS.Colors.muted.color)
                    // The note is the row's one multi-line element; it wraps
                    // rather than truncating, and the layout caps how wide it
                    // is allowed to get.
                    .fixedSize(horizontal: false, vertical: true)
            }
            // One subview whatever the caller passes, which is what the layout
            // counts on. The label rides on the control rather than on the row,
            // so a segmented or menu picker keeps a VoiceOver element per option.
            HStack(spacing: DS.Space.s8) { control() }
                .accessibilityLabel(label)
        }
        .padding(.horizontal, DS.Space.s16)
        // 12 rather than nothing: a row whose note runs to three lines used to
        // sit hard against the hairlines above and below it.
        .padding(.vertical, DS.Space.s12)
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

/// Label (and optional note) on the left, control on the right, both centred
/// in the row.
///
/// It exists for one reason: the note is offered at most `noteWidthFraction` of
/// the *row*, so a long one wraps early instead of running all the way up to
/// the control. Nothing composed of stacks can express that — a stack only
/// knows the width left after its siblings — and measuring the row in view
/// state costs a settling pass the fit tests would have to work around.
///
/// Subview order is label · note (optional) · control, and the control is
/// always the last one.
struct SettingsRowLayout: Layout {
    /// Widest the note may get, as a fraction of the row.
    static let noteWidthFraction: CGFloat = 0.6
    /// Gap between the label and its note.
    static let labelNoteSpacing: CGFloat = DS.Space.s4

    /// Smallest gap between the text column and the control.
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let m = measure(width: proposal.width, subviews: subviews)
        // An unbounded or infinite proposal gets the row's ideal width, the
        // same guard `measure` applies — returning `.infinity` here would hand
        // an infinite width to whatever is measuring the card.
        let ideal = m.text.width + spacing + m.control.width
        let width = (proposal.width?.isFinite ?? false) ? proposal.width! : ideal
        return CGSize(width: width, height: max(m.text.height, m.control.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let m = measure(width: bounds.width, subviews: subviews)
        var y = bounds.midY - m.text.height / 2
        subviews[0].place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: ProposedViewSize(m.label))
        if subviews.count > 2 {
            y += m.label.height + Self.labelNoteSpacing
            subviews[1].place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: ProposedViewSize(m.note))
        }
        subviews[subviews.count - 1].place(
            at: CGPoint(x: bounds.maxX - m.control.width, y: bounds.midY - m.control.height / 2),
            anchor: .topLeading, proposal: ProposedViewSize(m.control)
        )
    }

    /// `width` is the row's width; `nil` means an unbounded proposal, and the
    /// note is then measured at its ideal width like everything else.
    private func measure(width: CGFloat?, subviews: Subviews) -> (label: CGSize, note: CGSize, text: CGSize, control: CGSize) {
        let control = subviews[subviews.count - 1].sizeThatFits(.unspecified)
        let row: CGFloat? = (width?.isFinite ?? false) ? width : nil
        let leftover = row.map { max(0, $0 - spacing - control.width) }

        // The label gets everything the control leaves: a wrapped label reads
        // as a mistake, while a wrapped note reads as a paragraph.
        let label = subviews[0].sizeThatFits(ProposedViewSize(width: leftover, height: nil))
        guard subviews.count > 2 else { return (label, .zero, label, control) }

        let noteWidth = zip2(leftover, row).map { min($0, $1 * Self.noteWidthFraction) }
        let note = subviews[1].sizeThatFits(ProposedViewSize(width: noteWidth, height: nil))
        let text = CGSize(width: max(label.width, note.width),
                          height: label.height + Self.labelNoteSpacing + note.height)
        return (label, note, text, control)
    }

    private func zip2(_ a: CGFloat?, _ b: CGFloat?) -> (CGFloat, CGFloat)? {
        guard let a, let b else { return nil }
        return (a, b)
    }
}
