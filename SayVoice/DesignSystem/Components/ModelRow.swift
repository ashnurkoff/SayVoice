import SwiftUI

/// One selectable model in the recognition list. Takes plain values: the
/// feature view maps the model catalogue onto them.
///
/// Row: selection indicator · name · badge · quality bar · downloaded · size,
/// with an optional one-line note under the name. A further line hosts
/// `DownloadProgress` when a download is offered or running. Selection tint is
/// the accent (the "active control" place).
struct ModelRow: View {
    let name: String
    /// What the model is for, in `caption`/`muted` under the name. Wraps rather
    /// than truncates: it is the only place the row explains itself.
    let note: String?
    let badge: String?
    let badgeIsAccent: Bool
    let qualitySteps: Int
    let sizeText: String
    let isSelected: Bool
    let isDownloaded: Bool
    let isHighlighted: Bool
    /// Off where the row has no width to spare — the onboarding pane.
    let showsQualityBar: Bool
    /// Tighter vertical padding, for the onboarding pane where five rows with
    /// their notes and a download line have to share one window.
    let isCompact: Bool
    let download: DownloadState?
    /// Passed to `DownloadProgress`: only one row on a screen may be primary.
    let downloadIsProminent: Bool
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void

    init(
        name: String, note: String? = nil, badge: String? = nil, badgeIsAccent: Bool = false,
        qualitySteps: Int, sizeText: String,
        isSelected: Bool, isDownloaded: Bool, isHighlighted: Bool = false, showsQualityBar: Bool = true,
        isCompact: Bool = false, download: DownloadState?, downloadIsProminent: Bool = true,
        onSelect: @escaping () -> Void, onDownload: @escaping () -> Void,
        onCancel: @escaping () -> Void, onRetry: @escaping () -> Void
    ) {
        self.name = name; self.note = note; self.badge = badge; self.badgeIsAccent = badgeIsAccent
        self.qualitySteps = qualitySteps; self.sizeText = sizeText
        self.isSelected = isSelected; self.isDownloaded = isDownloaded; self.isHighlighted = isHighlighted
        self.showsQualityBar = showsQualityBar; self.isCompact = isCompact
        self.download = download; self.downloadIsProminent = downloadIsProminent
        self.onSelect = onSelect; self.onDownload = onDownload; self.onCancel = onCancel; self.onRetry = onRetry
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s8) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: DS.Space.s12) {
                        indicator
                        Text(name)
                            .font(DS.font(isSelected ? .bodyMedium : .body))
                            .foregroundStyle(DS.Colors.text.color)
                            // One line: a long name truncates rather than pushing
                            // the size chip out of the row.
                            .lineLimit(1)
                        if let badge {
                            Chip(badge, style: badgeIsAccent ? .accent : .neutral)
                        }
                        if showsQualityBar { qualityBar }
                        Spacer(minLength: DS.Space.s12)
                        if isDownloaded {
                            Chip("downloaded", style: .ok)
                        }
                        Chip(sizeText)
                    }
                    if let note {
                        Text(note)
                            .font(DS.font(.caption))
                            .foregroundStyle(DS.Colors.muted.color)
                            .multilineTextAlignment(.leading)
                            // Wraps, never truncates: a cut-off explanation is
                            // worse than none. It runs the width of the row
                            // rather than the width the name leaves, and starts
                            // under the name, past the indicator.
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 28)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let download, !isDownloaded {
                DownloadProgress(state: download, prominent: downloadIsProminent,
                                 onStart: onDownload, onCancel: onCancel, onRetry: onRetry)
                    .padding(.leading, 28)   // aligns with the name, past the indicator
            }
        }
        .padding(.horizontal, DS.Space.s12)
        .padding(.vertical, isCompact ? DS.Space.s4 : DS.Space.s8)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                .fill(isSelected ? DS.Colors.accentSoft.color : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                // Highlight wins over selection: the coordinator highlights the
                // *selected* model when it is missing, and an accent border
                // there would show nothing new.
                .strokeBorder(isHighlighted ? DS.Colors.warn.color : (isSelected ? DS.Colors.accent.color : DS.Colors.line.color), lineWidth: 1)
        )
        .animation(DS.Motion.stateChange, value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var indicator: some View {
        ZStack {
            Circle().strokeBorder(isSelected ? DS.Colors.accent.color : DS.Colors.faint.color, lineWidth: 1.5)
            if isSelected {
                Circle().fill(DS.Colors.accent.color).padding(4)
            }
        }
        .frame(width: 16, height: 16)
    }

    /// Five segments; filled ones show relative quality.
    private var qualityBar: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(i < qualitySteps ? DS.Colors.muted.color : DS.Colors.line.color)
                    .frame(width: 14, height: 4)
            }
        }
        // Clamped: the label must stay truthful even if a catalogue entry ever
        // carries a step outside the scale.
        .accessibilityLabel("Quality \(min(5, max(1, qualitySteps))) of 5")
    }
}
