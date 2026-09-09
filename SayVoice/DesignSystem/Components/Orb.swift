import SwiftUI

/// The single state indicator of the app. It appears in the overlay, in the
/// history popover header and (rendered to an image) in the menu bar.
///
/// Recording pulses, transcribing breathes; both stop under Reduce Motion
/// and are replaced by a steady colour.
struct Orb: View {
    enum State: Equatable { case idle, recording, transcribing, done, error }

    let state: State
    var size: CGFloat = DS.Size.orb

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SwiftUI.State private var phase = false

    /// Halo ring width around the orb; part of the frame so layout is stable.
    private let halo: CGFloat = 5

    init(state: State, size: CGFloat = DS.Size.orb) {
        self.state = state
        self.size = size
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(haloColor)
                .frame(width: size + halo * 2, height: size + halo * 2)
                .scaleEffect(pulseScale)
                .opacity(pulseOpacity)

            Circle()
                .fill(gradient)
                .frame(width: size, height: size)
                .scaleEffect(breathScale)

            glyph
        }
        .frame(width: size + halo * 2, height: size + halo * 2)
        .animation(DS.Motion.orb, value: state)
        .onAppear(perform: startMotion)
        .onChange(of: state) { _, _ in startMotion() }
        .accessibilityLabel(label)
    }

    // MARK: - Looks

    private var gradient: RadialGradient {
        let (top, base): (Color, Color)
        switch state {
        case .idle, .transcribing: (top, base) = (DS.Colors.accent2.color, DS.Colors.accent.color)
        case .recording:           (top, base) = (DS.Colors.recHighlight.color, DS.Colors.rec.color)
        case .done:                (top, base) = (DS.Colors.okHighlight.color, DS.Colors.ok.color)
        case .error:               (top, base) = (DS.Colors.warnHighlight.color, DS.Colors.warn.color)
        }
        return RadialGradient(colors: [top, base], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size)
    }

    private var haloColor: Color {
        switch state {
        case .idle, .transcribing: return DS.Colors.accentSoft.color
        case .recording:           return DS.Colors.rec.color.opacity(0.25)
        case .done:                return DS.Colors.ok.color.opacity(0.22)
        case .error:               return DS.Colors.warn.color.opacity(0.22)
        }
    }

    @ViewBuilder private var glyph: some View {
        switch state {
        case .done:
            Image(systemName: "checkmark").font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(.white)
        case .error:
            Image(systemName: "exclamationmark").font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(.white)
        case .recording:
            Circle().fill(.white).frame(width: size * 0.3, height: size * 0.3)
        case .idle, .transcribing:
            EmptyView()
        }
    }

    private var label: String {
        switch state {
        case .idle: return "Ready"
        case .recording: return "Recording"
        case .transcribing: return "Transcribing"
        case .done: return "Done"
        case .error: return "Error"
        }
    }

    // MARK: - Motion

    private var pulseScale: CGFloat {
        guard state == .recording, !reduceMotion else { return 1 }
        return phase ? 1.35 : 1.0
    }

    private var pulseOpacity: Double {
        guard state == .recording, !reduceMotion else { return 1 }
        return phase ? 0.0 : 1.0
    }

    private var breathScale: CGFloat {
        guard state == .transcribing, !reduceMotion else { return 1 }
        return phase ? 1.06 : 0.96
    }

    private func startMotion() {
        phase = false
        guard !reduceMotion else { return }
        switch state {
        case .recording:
            withAnimation(.easeOut(duration: DS.Motion.pulseDuration).repeatForever(autoreverses: false)) { phase = true }
        case .transcribing:
            withAnimation(.easeInOut(duration: DS.Motion.breathDuration / 2).repeatForever(autoreverses: true)) { phase = true }
        case .idle, .done, .error:
            break
        }
    }
}
