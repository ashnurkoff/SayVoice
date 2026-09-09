import SwiftUI

/// Icon rail: logo mark on top, one icon per section. The selected item uses
/// the accent (active control); the rest are neutral.
struct SettingsRail: View {
    let selected: SettingsSection
    let onSelect: (SettingsSection) -> Void

    var body: some View {
        VStack(spacing: 6) {
            LogoMark()
                .padding(.top, DS.Space.s12)
                .padding(.bottom, DS.Space.s8)

            ForEach(SettingsSection.allCases) { section in
                Button { onSelect(section) } label: {
                    Image(systemName: section.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(section == selected ? DS.Colors.accent.color : DS.Colors.muted.color)
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(section == selected ? DS.Colors.accentSoft.color : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(section.title)
                .accessibilityLabel(section.title)
                .accessibilityAddTraits(section == selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
        // The buttons make the stack only 40 pt wide; without this the rail
        // chrome — and its trailing hairline — would float inside the 64 pt rail.
        .frame(maxWidth: .infinity)
        .background(DS.Colors.surface2.color.opacity(0.5))
        .overlay(alignment: .trailing) { Rectangle().fill(DS.Colors.line.color).frame(width: 1) }
    }
}

/// The brand mark: accent gradient tile — the one place besides the orb where
/// the gradient is allowed.
struct LogoMark: View {
    var size: CGFloat = 36
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(LinearGradient(colors: [DS.Colors.accent.color, DS.Colors.accent2.color], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "waveform")
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .shadow(color: DS.Colors.glassShadow.color, radius: 6, x: 0, y: 3)
            .accessibilityLabel("SayVoice")
    }
}
