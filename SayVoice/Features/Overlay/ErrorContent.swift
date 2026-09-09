import SwiftUI

/// Orb error · message · optional action button (e.g. Open System Settings).
struct ErrorContent: View {
    let model: OverlayModel

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.s12) {
            Orb(state: .error)

            Text(model.message)
                .font(DS.font(.bodyLarge))
                .foregroundStyle(DS.Colors.text.color)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let action = model.errorAction {
                Spacer(minLength: DS.Space.s8)
                Button(action.title, action: action.handler).buttonStyle(.dsSecondary)
            }
        }
    }
}
