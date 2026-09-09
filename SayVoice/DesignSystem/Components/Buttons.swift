import SwiftUI

/// Button styles in token colours. Pressed state dims; disabled state fades.
/// Primary and Link use the accent (spec §3.1: interactive controls); at most one primary per screen.
struct DSPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.font(.bodyMedium))
            .foregroundStyle(DS.Colors.onAccent.color)
            .padding(.horizontal, DS.Space.s16)
            .padding(.vertical, DS.Space.s8)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                    .fill(DS.Colors.accent.color)
            )
            .opacity(configuration.isPressed ? 0.85 : (isEnabled ? 1 : 0.45))
            .animation(DS.Motion.stateChange, value: configuration.isPressed)
    }
}

struct DSSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.font(.bodyMedium))
            .foregroundStyle(DS.Colors.text.color)
            .padding(.horizontal, DS.Space.s12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                    .fill(DS.Colors.surface2.color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                    .strokeBorder(DS.Colors.line.color, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : (isEnabled ? 1 : 0.45))
            .animation(DS.Motion.stateChange, value: configuration.isPressed)
    }
}

struct DSLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.font(.bodyMedium))
            .foregroundStyle(DS.Colors.accent.color)
            .padding(.vertical, 4)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct DSDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.font(.bodyMedium))
            .foregroundStyle(DS.Colors.rec.color)
            .padding(.vertical, 4)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == DSPrimaryButtonStyle {
    static var dsPrimary: DSPrimaryButtonStyle { .init() }
}
extension ButtonStyle where Self == DSSecondaryButtonStyle {
    static var dsSecondary: DSSecondaryButtonStyle { .init() }
}
extension ButtonStyle where Self == DSLinkButtonStyle {
    static var dsLink: DSLinkButtonStyle { .init() }
}
extension ButtonStyle where Self == DSDestructiveButtonStyle {
    static var dsDestructive: DSDestructiveButtonStyle { .init() }
}
