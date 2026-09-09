import SwiftUI

/// The single state indicator of the app. It appears in the overlay, in the
/// history popover header and (rendered to an image) in the menu bar.
///
/// Recording pulses, transcribing breathes, and the done mark draws itself in
/// once — a spring from 0.6 to full size with one halo pulse behind it. All
/// three stop under Reduce Motion and are replaced by a steady colour.
struct Orb: View {
    enum State: Equatable { case idle, recording, transcribing, done, error }

    let state: State
    var size: CGFloat = DS.Size.orb

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dsStaticMotion) private var staticMotion

    /// Motion is off under the system setting and under the renderer's switch.
    private var reduceMotion: Bool { systemReduceMotion || staticMotion }
    @SwiftUI.State private var phase = false
    /// Whether the done mark has finished drawing itself in. Read only in the
    /// done state; every other state is at rest from its first frame.
    @SwiftUI.State private var drawnIn = false

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

            ZStack {
                Circle()
                    .fill(gradient)
                    .frame(width: size, height: size)
                    .scaleEffect(breathScale)

                glyph
            }
            // The entrance applies to the mark, not to the halo: the halo has
            // its own one-shot pulse to run behind it.
            .scaleEffect(Self.drawInScale(state: state, drawnIn: drawnIn, reduceMotion: reduceMotion))
            .opacity(Self.drawInOpacity(state: state, drawnIn: drawnIn, reduceMotion: reduceMotion))
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
            Image(systemName: "checkmark").font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(DS.Colors.onAccent.color)
        case .error:
            Image(systemName: "exclamationmark").font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(DS.Colors.onAccent.color)
        case .recording:
            Circle().fill(DS.Colors.onAccent.color).frame(width: size * 0.3, height: size * 0.3)
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

    /// Scale of the mark while it draws itself in: 0.6 before, 1 after. Only
    /// the done state has an entrance, and Reduce Motion removes it — the mark
    /// is then simply there, which is the point of the setting.
    static func drawInScale(state: State, drawnIn: Bool, reduceMotion: Bool) -> CGFloat {
        isDrawingIn(state: state, drawnIn: drawnIn, reduceMotion: reduceMotion) ? 0.6 : 1
    }

    /// Opacity of the mark while it draws itself in: 0 before, 1 after.
    static func drawInOpacity(state: State, drawnIn: Bool, reduceMotion: Bool) -> Double {
        isDrawingIn(state: state, drawnIn: drawnIn, reduceMotion: reduceMotion) ? 0 : 1
    }

    static func isDrawingIn(state: State, drawnIn: Bool, reduceMotion: Bool) -> Bool {
        state == .done && !drawnIn && !reduceMotion
    }

    /// The halo pulses out and fades: forever while recording, once behind the
    /// done mark.
    private var pulses: Bool { state == .recording || state == .done }

    private var pulseScale: CGFloat {
        guard pulses, !reduceMotion else { return 1 }
        return phase ? 1.35 : 1.0
    }

    private var pulseOpacity: Double {
        guard pulses, !reduceMotion else { return 1 }
        return phase ? 0.0 : 1.0
    }

    private var breathScale: CGFloat {
        guard state == .transcribing, !reduceMotion else { return 1 }
        return phase ? 1.06 : 0.96
    }

    private func startMotion() {
        phase = false
        guard !reduceMotion else {
            drawnIn = true
            return
        }
        switch state {
        case .recording:
            withAnimation(.easeOut(duration: DS.Motion.pulseDuration).repeatForever(autoreverses: false)) { phase = true }
        case .transcribing:
            withAnimation(.easeInOut(duration: DS.Motion.breathDuration / 2).repeatForever(autoreverses: true)) { phase = true }
        case .done:
            // Once: the check springs up to full size while a single halo pulse
            // travels out behind it.
            drawnIn = false
            withAnimation(DS.Motion.orb) { drawnIn = true }
            withAnimation(.easeOut(duration: DS.Motion.pulseDuration)) { phase = true }
        case .idle, .error:
            drawnIn = true
        }
    }
}
