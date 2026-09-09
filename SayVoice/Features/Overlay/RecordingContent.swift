import SwiftUI

/// Orb · "Listening" + hint · waveform · timer (· Stop in toggle mode).
struct RecordingContent: View {
    let model: OverlayModel

    var body: some View {
        HStack(spacing: DS.Space.s12) {
            Orb(state: .recording)

            VStack(alignment: .leading, spacing: 1) {
                Text("Listening")
                    .font(DS.font(.bodyLarge))
                    .foregroundStyle(DS.Colors.text.color)
                Text(hint)
                    .font(DS.font(.caption))
                    .foregroundStyle(DS.Colors.muted.color)
                    .lineLimit(1)
            }
            // No fixedSize: at 420 pt a long hotkey name must truncate rather
            // than push the row out of the glass.
            .layoutPriority(0)

            // Yields width first — it is decoration, the timer and Stop are not.
            Waveform(levels: model.levelHistory, bars: model.isToggleMode ? 12 : 20, tint: DS.Colors.rec.color)
                .frame(height: 22)
                .frame(minWidth: 40, maxWidth: .infinity)
                .layoutPriority(-1)

            RecordingTimer(startDate: model.recordingStart)
                .layoutPriority(1)

            if model.isToggleMode {
                Button("Stop") { model.onStop?() }
                    .buttonStyle(.dsSecondary)
                    .layoutPriority(1)
            }
        }
    }

    private var hint: String {
        let key = model.hotkeyName.isEmpty ? "the hotkey" : model.hotkeyName
        return model.isToggleMode ? "Press \(key) again to finish" : "Release \(key) to finish"
    }
}

/// Elapsed time, updated once a second. Tabular digits so it does not jitter.
struct RecordingTimer: View {
    let startDate: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(startDate))
            Text(String(format: "%d:%02d", Int(elapsed) / 60, Int(elapsed) % 60))
                .font(DS.font(.value))
                .foregroundStyle(DS.Colors.text.color)
        }
    }
}
