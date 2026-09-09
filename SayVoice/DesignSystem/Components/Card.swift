import SwiftUI

/// Settings card: optional title/subtitle header, then rows separated by hairlines.
struct Card<Content: View>: View {
    let title: String?
    let subtitle: String?
    @ViewBuilder let content: () -> Content

    init(title: String? = nil, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let title { Text(title).font(DS.font(.title)).foregroundStyle(DS.Colors.text.color) }
                    if let subtitle { Text(subtitle).font(DS.font(.caption)).foregroundStyle(DS.Colors.muted.color) }
                }
                .padding(.horizontal, DS.Space.s16)
                .padding(.top, DS.Space.s16)
                .padding(.bottom, DS.Space.s8)
            }
            content()
        }
        .padding(.bottom, DS.Space.s8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).fill(DS.Colors.surface.color))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).strokeBorder(DS.Colors.line.color, lineWidth: 1))
        .shadow(color: DS.Colors.cardShadow.color, radius: 2, x: 0, y: 1)
    }
}
