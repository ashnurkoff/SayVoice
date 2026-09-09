import SwiftUI

/// Small capsule label: "recommended", "574 MB", "downloaded".
/// Neutral by default; `.accent` is reserved for the recommended model.
struct Chip: View {
    enum Style { case neutral, accent, ok, warn }

    let text: String
    var style: Style = .neutral

    init(_ text: String, style: Style = .neutral) {
        self.text = text
        self.style = style
    }

    var body: some View {
        Text(text)
            .font(DS.font(.valueSmall))
            .foregroundStyle(foreground)
            .padding(.horizontal, DS.Space.s8)
            .padding(.vertical, 3)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(border, lineWidth: 1))
    }

    private var foreground: Color {
        switch style {
        case .neutral: return DS.Colors.muted.color
        case .accent:  return DS.Colors.accent.color
        case .ok:      return DS.Colors.ok.color
        case .warn:    return DS.Colors.warn.color
        }
    }

    private var fill: Color {
        switch style {
        case .neutral: return DS.Colors.surface2.color
        case .accent:  return DS.Colors.accentSoft.color
        case .ok:      return DS.Colors.ok.color.opacity(0.12)
        case .warn:    return DS.Colors.warn.color.opacity(0.14)
        }
    }

    private var border: Color {
        switch style {
        case .neutral: return DS.Colors.line.color
        case .accent:  return DS.Colors.accent.color.opacity(0.35)
        case .ok:      return DS.Colors.ok.color.opacity(0.3)
        case .warn:    return DS.Colors.warn.color.opacity(0.3)
        }
    }
}
