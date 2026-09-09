import AppKit
import SwiftUI

/// One dictation: two-line text, meta line, Copy on hover → "Copied".
struct HistoryRow: View {
    let entry: TranscriptionEntry
    @State private var hovering = false
    @State private var copied = false
    @State private var copyReset: Task<Void, Never>?

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.s8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.text)
                    .font(DS.font(.body)).foregroundStyle(DS.Colors.text.color)
                    .lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: DS.Space.s8) {
                    Text(RelativeTime.coarse(entry.date))
                    Text(String(format: "%.1f s", entry.durationSeconds))
                    if let lang = entry.language { Chip(lang.uppercased()) }
                }
                .font(DS.font(.valueSmall)).foregroundStyle(DS.Colors.muted.color)
            }
            Spacer(minLength: 0)
            if copied {
                Chip("Copied", style: .ok)
            } else if hovering {
                Button("Copy", action: copy).buttonStyle(.dsLink)
            }
        }
        .padding(.horizontal, DS.Space.s12)
        .padding(.vertical, DS.Space.s8)
        .frame(minHeight: DS.Size.popoverRow)
        .contentShape(Rectangle())
        .background(RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
            .fill(hovering ? DS.Colors.surface2.color : Color.clear))
        .onHover { hovering = $0 }
        .animation(DS.Motion.stateChange, value: hovering)
        .animation(DS.Motion.stateChange, value: copied)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Copy", copy)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        copied = true
        // A second copy restarts the window instead of letting the first
        // timer clear the chip while the confirmation is still fresh.
        copyReset?.cancel()
        copyReset = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}
