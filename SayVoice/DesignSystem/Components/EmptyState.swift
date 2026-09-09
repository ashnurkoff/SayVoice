import SwiftUI

/// Centered symbol, title and hint for an empty list. Neutral colours only.
struct EmptyState: View {
    let symbol: String
    let title: String
    let hint: String

    var body: some View {
        VStack(spacing: DS.Space.s8) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(DS.Colors.faint.color)
            Text(title).font(DS.font(.bodyMedium)).foregroundStyle(DS.Colors.text.color)
            Text(hint).font(DS.font(.caption)).foregroundStyle(DS.Colors.muted.color)
                .multilineTextAlignment(.center)
        }
        .padding(DS.Space.s20)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
