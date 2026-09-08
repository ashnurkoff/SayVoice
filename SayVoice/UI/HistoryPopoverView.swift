import AppKit
import SwiftUI

struct HistoryPopoverView: View {
    let entries: [TranscriptionEntry]
    var onClear: () -> Void
    var onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label("SayVoice", systemImage: "waveform")
                    .font(.headline)
                Spacer()
                Button(action: onSettings) {
                    Image(systemName: "gear")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // History list
            if entries.isEmpty {
                VStack(spacing: 4) {
                    Text("Нет записей")
                        .foregroundStyle(.secondary)
                    Text("Зажмите Right Option для записи")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            HistoryRowView(entry: entry)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 300)
            }

            Divider()

            // Footer
            HStack {
                if !entries.isEmpty {
                    Button("Очистить") { onClear() }
                        .foregroundStyle(.red)
                        .buttonStyle(.plain)
                        .font(.caption)
                }
                Spacer()
                Button("Настройки...") { onSettings() }
                    .buttonStyle(.plain)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 320)
    }
}

struct HistoryRowView: View {
    let entry: TranscriptionEntry
    @State private var copied = false

    var body: some View {
        Button(action: copyToClipboard) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.text)
                        .font(.system(size: 12))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 4) {
                        Text(entry.date, style: .relative)
                        Text("\u{00B7}")
                        Text("\(entry.durationSeconds, specifier: "%.1f")с")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        withAnimation { copied = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { copied = false }
        }
    }
}
