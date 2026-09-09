import AppKit
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
    /// Height the rows actually need, reported by the list itself. Zero until
    /// the first layout pass has measured it, and the list then falls back to
    /// filling the cap — never to nothing.
    @State private var listHeight: CGFloat = 0

    private var shown: [TranscriptionEntry] { HistoryFilter.apply(entries, query: query) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.s8) {
                LogoMark(size: 22)
                Text("SayVoice").font(DS.font(.bodyMedium)).foregroundStyle(DS.Colors.text.color)
                Spacer(minLength: DS.Space.s8)
                StatusPill(status: status, compact: true)
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
                    // A ScrollView takes every point it is offered, so the cap
                    // alone made one dictation open a popover two thirds empty.
                    // The list measures itself and the frame below hugs it.
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
                }
                .frame(height: listHeight > 0 ? min(listHeight, Self.listMaxHeight) : nil)
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
        // The search field's caret and selection, and anything a future row
        // adds, follow the app accent rather than the system one.
        .tint(DS.Colors.accent.color)
    }

    #if DEBUG
    /// Test/render hook: the fitting size once the list's measured height has
    /// reached the view state. The first layout pass runs before that
    /// measurement exists and reports the capped fallback, so the size is read
    /// again until it stops moving.
    static func settledFittingSize(of host: NSView, passes: Int = 8) -> NSSize {
        host.frame = CGRect(x: 0, y: 0, width: width, height: listMaxHeight * 2)
        var last = NSSize.zero
        for _ in 0..<passes {
            host.layoutSubtreeIfNeeded()
            let size = host.fittingSize
            if size.height > 0, abs(size.height - last.height) < 0.5 { return size }
            last = size
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return last
    }
    #endif
}
