import SwiftUI

/// Left panel of the onboarding window: the brand gradient, a large white
/// waveform and one dot per step. The one place besides the orb and the logo
/// mark where the accent gradient is allowed.
struct ArtPanel: View {
    static let width: CGFloat = 240
    let step: OnboardingStep

    var body: some View {
        ZStack {
            LinearGradient(colors: [DS.Colors.accent.color, DS.Colors.accent2.color],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: DS.Space.s20) {
                Spacer(minLength: 0)
                Image(systemName: "waveform")
                    .font(.system(size: 88, weight: .semibold))
                    .foregroundStyle(DS.Colors.onAccent.color.opacity(0.95))
                Text("SayVoice")
                    .font(DS.font(.title))
                    .foregroundStyle(DS.Colors.onAccent.color)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    ForEach(OnboardingStep.allCases, id: \.self) { s in
                        Capsule()
                            .fill(DS.Colors.onAccent.color.opacity(s == step ? 0.95 : 0.35))
                            .frame(width: s == step ? 18 : 6, height: 6)
                    }
                }
                .padding(.bottom, DS.Space.s20)
                .animation(DS.Motion.stateChange, value: step)
            }
        }
        .frame(width: Self.width)
        .accessibilityHidden(true)
    }
}
