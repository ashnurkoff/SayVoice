import SwiftUI

/// One selectable model in the recognition list. Takes plain values: the
/// feature view maps the model catalogue onto them.
///
/// Two columns, no chips (owner's second live test — three capsules per row
/// made the list read as a form). Left: the selection indicator, the name, and
/// for the recommended model one accent word after it; the purpose note runs
/// under them. Right, right-aligned: the size as plain text, the quality bar as
/// five dots in Settings, and the row's download status — "Downloaded" or the
/// Download button. A running or failed transfer takes a full-width line under
/// both columns, the only line a row ever grows.
struct ModelRow: View {
    let name: String
    /// What the model is for, in `caption`/`muted` under the name. Wraps rather
    /// than truncates: it is the only place the row explains itself.
    let note: String?
    /// One word beside the name — "Recommended". Text, not a capsule.
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
    /// Whether this row's Download button is the screen's primary action: only
    /// one row on a screen may be primary (spec §3.1).
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
            HStack(alignment: .top, spacing: DS.Space.s12) {
                // Only the left column is the selection button: the right one
                // carries a real Download button, and a button inside a
                // button's label never gets the click.
                Button(action: onSelect) {
                    HStack(alignment: .top, spacing: DS.Space.s12) {
                        indicator
                        VStack(alignment: .leading, spacing: 2) {
                            nameLine
                            if let note { noteText(note) }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Combined here rather than on the whole row: combining across
                // the status column would swallow the Download button's action.
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isSelected ? .isSelected : [])

                statusColumn
            }

            if showsTransferLine, let download {
                DownloadProgress(state: download, prominent: downloadIsProminent,
                                 onStart: onDownload, onCancel: onCancel, onRetry: onRetry)
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
    }

    // MARK: - Left column

    private var nameLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s8) {
            Text(name)
                .font(DS.font(.bodyMedium))
                .foregroundStyle(DS.Colors.text.color)
                // One line: a long name truncates rather than pushing the size
                // out of the row.
                .lineLimit(1)
            if let badge {
                Text(badge)
                    .font(DS.font(.caption))
                    .foregroundStyle(badgeIsAccent ? DS.Colors.accent.color : DS.Colors.muted.color)
                    .lineLimit(1)
                    // Never the part that gets truncated: it is one word.
                    .fixedSize()
            }
        }
    }

    private func noteText(_ note: String) -> some View {
        Text(note)
            .font(DS.font(.caption))
            .foregroundStyle(DS.Colors.muted.color)
            .multilineTextAlignment(.leading)
            // Wraps, never truncates: a cut-off explanation is worse than none.
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var indicator: some View {
        ZStack {
            Circle().strokeBorder(isSelected ? DS.Colors.accent.color : DS.Colors.faint.color, lineWidth: 1.5)
            if isSelected {
                Circle().fill(DS.Colors.accent.color).padding(4)
            }
        }
        .frame(width: 16, height: 16)
        // Sits on the name's line rather than on the top of its line box.
        .padding(.top, 1)
    }

    // MARK: - Right column

    /// Size, then the quality dots in Settings, then the status. Two pt apart:
    /// the dots are a 4 pt graphic, and on the scale's spacing they would add
    /// twelve points to every row in the list.
    private var statusColumn: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(sizeText)
                .font(DS.font(.valueSmall))
                .foregroundStyle(DS.Colors.muted.color)
                .fixedSize()
                // Tapping the size, the dots or the mark selects the row, as it
                // did when the whole row was one button. The gestures sit on
                // those three and not on the column, so nothing competes with
                // the Download button for a click.
                .onTapGesture(perform: onSelect)
            if showsQualityBar { qualityDots }
            statusView
        }
    }

    @ViewBuilder private var statusView: some View {
        if isDownloaded || download == .done {
            Label("Downloaded", systemImage: "checkmark")
                .labelStyle(.titleAndIcon)
                .font(DS.font(.caption))
                .foregroundStyle(DS.Colors.ok.color)
                .fixedSize()
                .onTapGesture(perform: onSelect)
        } else if download == .idle {
            // Its own control rather than `DownloadProgress`'s idle case: that
            // one spreads to the width it is given, and this button sits in a
            // column sized to its content.
            if downloadIsProminent {
                Button("Download", action: onDownload).buttonStyle(.dsPrimary)
            } else {
                Button("Download", action: onDownload).buttonStyle(.dsSecondary)
            }
        }
    }

    /// Five 4 pt dots; filled ones show relative quality.
    private var qualityDots: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .fill(i < qualitySteps ? DS.Colors.muted.color : DS.Colors.line.color)
                    .frame(width: 4, height: 4)
            }
        }
        // Clamped: the label must stay truthful even if a catalogue entry ever
        // carries a step outside the scale.
        .accessibilityLabel("Quality \(min(5, max(1, qualitySteps))) of 5")
        .onTapGesture(perform: onSelect)
    }

    /// A transfer under way, or one that failed, is the only thing that gets a
    /// line of its own: the bar, its status and Cancel need the whole row.
    private var showsTransferLine: Bool {
        guard !isDownloaded, let download else { return false }
        switch download {
        case .running, .failed: return true
        case .idle, .done:      return false
        }
    }
}
