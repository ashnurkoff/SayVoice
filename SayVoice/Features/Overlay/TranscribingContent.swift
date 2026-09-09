import SwiftUI

/// Orb breathing · "Transcribing…" · thin indeterminate bar where the
/// waveform was, so the capsule keeps its height and nothing jumps.
struct TranscribingContent: View {
    var body: some View {
        HStack(spacing: DS.Space.s12) {
            Orb(state: .transcribing)

            Text("Transcribing…")
                .font(DS.font(.bodyLarge))
                .foregroundStyle(DS.Colors.text.color)
                .fixedSize()

            ProgressView()
                .progressViewStyle(.linear)
                .tint(DS.Colors.muted.color)
                .frame(height: 22)
        }
    }
}
