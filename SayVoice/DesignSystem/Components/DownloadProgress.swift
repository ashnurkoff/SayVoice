import SwiftUI

/// Download lifecycle as seen by the UI. Feature code maps its transfer
/// stream onto these values; the component only renders them.
enum DownloadState: Equatable {
    case idle
    case running(fraction: Double, bytesPerSecond: Double?, secondsLeft: Double?)
    case failed(String)
    case done
}

/// One download control: a Download button, then a progress bar with
/// speed and time left and a Cancel link, then Retry on failure, then a
/// "Downloaded" chip. Used by the settings model list and by onboarding.
struct DownloadProgress: View {
    let state: DownloadState
    /// Whether the idle Download button is the screen's primary action. A list
    /// of these renders one primary at most (spec 3.1); the rest are secondary.
    let prominent: Bool
    let onStart: () -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void

    init(state: DownloadState, prominent: Bool = true, onStart: @escaping () -> Void,
         onCancel: @escaping () -> Void, onRetry: @escaping () -> Void) {
        self.state = state
        self.prominent = prominent
        self.onStart = onStart
        self.onCancel = onCancel
        self.onRetry = onRetry
    }

    var body: some View {
        switch state {
        case .idle:
            HStack {
                Spacer(minLength: 0)
                if prominent {
                    Button("Download", action: onStart).buttonStyle(.dsPrimary)
                } else {
                    Button("Download", action: onStart).buttonStyle(.dsSecondary)
                }
            }

        case let .running(fraction, speed, eta):
            VStack(alignment: .leading, spacing: DS.Space.s8) {
                ProgressView(value: min(1, max(0, fraction)))
                    .progressViewStyle(.linear)
                    // Progress bars are neutral (spec 3.1): the highlight
                    // colour belongs to active controls, not to a transfer.
                    .tint(DS.Colors.muted.color)
                HStack {
                    Text(Self.statusText(fraction: fraction, bytesPerSecond: speed, secondsLeft: eta))
                        .font(DS.font(.valueSmall))
                        .foregroundStyle(DS.Colors.muted.color)
                    Spacer(minLength: DS.Space.s8)
                    Button("Cancel", action: onCancel).buttonStyle(.dsLink)
                }
            }

        case let .failed(message):
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s12) {
                Text(message)
                    .font(DS.font(.caption))
                    .foregroundStyle(DS.Colors.warn.color)
                    .lineLimit(2)
                Spacer(minLength: DS.Space.s8)
                Button("Retry", action: onRetry).buttonStyle(.dsSecondary)
            }

        case .done:
            HStack {
                Spacer(minLength: 0)
                Chip("downloaded", style: .ok)
            }
        }
    }

    /// "34% · 12.4 MB/s · 38 s left" — parts are omitted while unknown.
    /// Pure formatting, so it stays off the main actor and can be called
    /// from anywhere.
    nonisolated static func statusText(fraction: Double, bytesPerSecond: Double?, secondsLeft: Double?) -> String {
        // The epsilon keeps 0.29 from printing as "28%": the product is
        // 28.999… in binary, and flooring alone loses the point.
        let percent = Int((min(1, max(0, fraction)) * 100 + 1e-9).rounded(.down))
        var parts = ["\(percent)%"]
        if let bytesPerSecond, bytesPerSecond > 0 {
            parts.append(String(format: "%.1f MB/s", bytesPerSecond / 1_000_000))
        }
        if let secondsLeft, secondsLeft.isFinite, secondsLeft >= 0 {
            let eta = Self.etaText(secondsLeft)
            if !eta.isEmpty { parts.append(eta) }
        }
        return parts.joined(separator: " · ")
    }

    /// Minutes and hours are rounded, not truncated: 4000 s reads as
    /// "1 h 7 min left", which is what a user comparing the bar against a
    /// clock expects.
    /// An empty string when the estimate is absurd — a stalled transfer can
    /// produce billions of seconds, and converting that to `Int` traps.
    nonisolated private static func etaText(_ seconds: Double) -> String {
        guard seconds < 1e9 else { return "" }
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s) s left" }
        let minutes = Int((Double(s) / 60).rounded())
        if minutes < 60 { return "\(minutes) min left" }
        // "1 h 0 min left" is worse than "1 h left" in every way.
        if minutes % 60 == 0 { return "\(minutes / 60) h left" }
        return "\(minutes / 60) h \(minutes % 60) min left"
    }
}
