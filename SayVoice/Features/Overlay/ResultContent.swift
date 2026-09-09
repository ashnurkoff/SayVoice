import SwiftUI

/// Orb done · text (up to 4 lines) · Copy · Show all · duration.
struct ResultContent: View {
    let model: OverlayModel

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.s12) {
            Orb(state: .done)

            VStack(alignment: .leading, spacing: DS.Space.s8) {
                Text(model.message)
                    .font(DS.font(.bodyLarge))
                    .foregroundStyle(DS.Colors.text.color)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: DS.Space.s12) {
                    if let onCopy = model.onCopy {
                        Button("Copy", action: onCopy).buttonStyle(.dsLink)
                    }
                    if let onShowAll = model.onShowAll {
                        Button("Show all", action: onShowAll).buttonStyle(.dsLink)
                    }
                    Spacer(minLength: 0)
                    Text(String(format: "%.1f s", model.durationSeconds))
                        .font(DS.font(.valueSmall))
                        .foregroundStyle(DS.Colors.muted.color)
                }
            }
        }
    }
}
