import SwiftUI

/// Menu-bar popover: header with logo and status, search, recent dictations,
/// footer with Clear… and Settings. Width 320.
struct HistoryPopover: View {
    static let width: CGFloat = 320
    static let listMaxHeight: CGFloat = 360

    let entries: [TranscriptionEntry]
    let status: AppStatus
    let hotkeyName: String
    let onClear: () -> Void
    let onSettings: () -> Void

    @State private var query = ""
    @State private var confirmingClear = false

    private var shown: [TranscriptionEntry] { HistoryFilter.apply(entries, query: query) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.s8) {
                LogoMark(size: 22)
                Text("SayVoice").font(DS.font(.bodyMedium)).foregroundStyle(DS.Colors.text.color)
                Spacer(minLength: DS.Space.s8)
                StatusPill(status: status)
            }
            .padding(.horizontal, DS.Space.s12).padding(.vertical, DS.Space.s12)

            if !entries.isEmpty {
                TextField("Search", text: $query)
                    .textFieldStyle(.plain)
                    .font(DS.font(.body))
                    .padding(.horizontal, DS.Space.s12).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous).fill(DS.Colors.surface2.color))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous).strokeBorder(DS.Colors.line.color, lineWidth: 1))
                    .padding(.horizontal, DS.Space.s12).padding(.bottom, DS.Space.s8)
            }

            Rectangle().fill(DS.Colors.line.color).frame(height: 1)

            if entries.isEmpty {
                EmptyState(symbol: "waveform", title: "No dictations yet", hint: "Hold \(hotkeyName) and speak — the text lands where your cursor is.")
            } else if shown.isEmpty {
                EmptyState(symbol: "magnifyingglass", title: "Nothing matches", hint: "Try another word.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(shown) { HistoryRow(entry: $0) }
                    }
                    .padding(DS.Space.s4)
                }
                .frame(maxHeight: Self.listMaxHeight)
            }

            Rectangle().fill(DS.Colors.line.color).frame(height: 1)

            HStack {
                if !entries.isEmpty {
                    Button("Clear…") { confirmingClear = true }.buttonStyle(.dsDestructive)
                        .confirmationDialog("Clear all dictations?", isPresented: $confirmingClear, titleVisibility: .visible) {
                            Button("Clear", role: .destructive, action: onClear)
                        } message: { Text("This removes the local history. Nothing else is affected.") }
                }
                Spacer(minLength: DS.Space.s8)
                Button("Settings", action: onSettings).buttonStyle(.dsSecondary)
            }
            .padding(.horizontal, DS.Space.s12).padding(.vertical, DS.Space.s8)
        }
        .frame(width: Self.width)
        .background(DS.Colors.ground.color)
        .font(DS.font(.body))
    }
}
