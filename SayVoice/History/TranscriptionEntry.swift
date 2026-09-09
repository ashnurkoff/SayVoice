import Foundation

struct TranscriptionEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let date: Date
    let text: String
    let durationSeconds: Double
    let language: String?   // "ru", "en", nil = auto

    init(text: String, durationSeconds: Double, language: String? = nil) {
        self.id = UUID()
        self.date = Date()
        self.text = text
        self.durationSeconds = durationSeconds
        self.language = language
    }
}
