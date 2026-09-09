import SwiftUI

/// Hotkey display in monospace on an inset cap: ⌃⌥⌘D, Right ⌥, F13.
struct KeyCap: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(DS.font(.value))
            .foregroundStyle(DS.Colors.text.color)
            .padding(.horizontal, DS.Space.s12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .fill(DS.Colors.surface2.color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .strokeBorder(DS.Colors.line.color, lineWidth: 1)
            )
    }
}
