import Foundation
import Observation

@MainActor @Observable
final class TranscriptionHistoryStore {
    private(set) var entries: [TranscriptionEntry] = []
    private let maxEntries = 500

    nonisolated static let storageURL: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SayVoice/history.json")
    }()

    init() {
        load()
    }

    func append(_ entry: TranscriptionEntry) {
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    // MARK: - Persistence

    private func save() {
        do {
            let dir = Self.storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entries)
            try data.write(to: Self.storageURL, options: .atomic)
        } catch {
            print("[SayVoice] History save failed: \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: Self.storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: Self.storageURL)
            entries = try JSONDecoder().decode([TranscriptionEntry].self, from: data)
        } catch {
            print("[SayVoice] History load failed: \(error)")
            entries = []
        }
    }
}
