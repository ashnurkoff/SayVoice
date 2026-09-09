import Foundation

enum HistoryFilter {
    /// Case-insensitive substring match on the text; blank query returns everything.
    static func apply(_ entries: [TranscriptionEntry], query: String) -> [TranscriptionEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return entries }
        return entries.filter { $0.text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}
