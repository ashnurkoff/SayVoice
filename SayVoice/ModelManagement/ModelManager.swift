import Foundation

/// Progress of one model download, in bytes so consumers can compute speed
/// and time remaining themselves.
struct ModelDownloadProgress: Sendable, Equatable {
    let bytesReceived: Int64
    let totalBytes: Int64

    /// 0…1; 0 while the total is unknown.
    var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(bytesReceived) / Double(totalBytes))
    }
}

@MainActor
final class ModelManager {

    enum ModelSize: String, CaseIterable, Sendable {
        case base       = "ggml-base"
        case small      = "ggml-small"
        case turboQ5    = "ggml-large-v3-turbo-q5_0"
        case turboQ8    = "ggml-large-v3-turbo-q8_0"
        case turbo      = "ggml-large-v3-turbo"

        /// Размеры сверены с HuggingFace API (десятичные МБ, как в Finder).
        var fileSize: String {
            switch self {
            case .base:    return "148 МБ"
            case .small:   return "488 МБ"
            case .turboQ5: return "574 МБ"
            case .turboQ8: return "874 МБ"
            case .turbo:   return "1.62 ГБ"
            }
        }

        /// Same numbers as `fileSize`, with English units — for the rewritten
        /// settings UI. `fileSize` stays as it is for the legacy screens.
        var sizeText: String {
            switch self {
            case .base:    return "148 MB"
            case .small:   return "488 MB"
            case .turboQ5: return "574 MB"
            case .turboQ8: return "874 MB"
            case .turbo:   return "1.62 GB"
            }
        }

        var displayName: String {
            switch self {
            case .base:    return "Base"
            case .small:   return "Small"
            case .turboQ5: return "Large Turbo Q5"
            case .turboQ8: return "Large Turbo Q8"
            case .turbo:   return "Large Turbo"
            }
        }

        /// Короткая пометка о назначении модели — бейдж рядом с названием.
        var badge: String {
            switch self {
            case .base:    return "самая быстрая"
            case .small:   return "лёгкая"
            case .turboQ5: return "рекомендуется"
            case .turboQ8: return "точнее"
            case .turbo:   return "максимум качества"
            }
        }

        /// Пояснение под списком — показывается для выбранной модели.
        var note: String {
            switch self {
            case .base:
                return "Самая быстрая и лёгкая. Годится для коротких английских фраз; на русской речи ошибается заметно чаще остальных, особенно в терминах и именах."
            case .small:
                return "Самая экономная из пригодных для диктовки. На смешанной русско-английской речи заметно уступает Turbo — английские термины часто пишет кириллицей."
            case .turboQ5:
                return "Оптимальный баланс: качество почти как у полной Turbo при трети её размера. На Apple Silicon расшифровывает минуту речи за несколько секунд."
            case .turboQ8:
                return "Та же модель, что и Q5, но с более точным квантованием — чуть аккуратнее с редкими словами и именами. Вдвое меньше полной Turbo."
            case .turbo:
                return "Модель без квантования — эталон качества для этого семейства. Занимает больше всех места и дольше грузится в память после простоя."
            }
        }

        var fileName: String { "\(rawValue).bin" }

        var downloadURL: URL {
            URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
        }

        /// Строка для UserDefaults (см. SettingsStore.modelSize).
        var settingsString: String {
            switch self {
            case .base:    return "base"
            case .small:   return "small"
            case .turboQ5: return "large-v3-turbo-q5"
            case .turboQ8: return "large-v3-turbo-q8"
            case .turbo:   return "large-v3-turbo"
            }
        }

        /// Конвертация из строки настроек в enum.
        /// Tiny убрана из списка: на русской речи даёт кашу, а выигрыш в скорости на
        /// Apple Silicon не нужен — Turbo Q5 расшифровывает быстрее реального времени.
        /// Сохранённый выбор "tiny" переводим на ближайшую оставшуюся — Base.
        init?(settingsString: String) {
            switch settingsString {
            case "base":               self = .base
            case "small":              self = .small
            case "large-v3-turbo-q5":  self = .turboQ5
            case "large-v3-turbo-q8":  self = .turboQ8
            case "large-v3-turbo":     self = .turbo
            case "tiny":               self = .base
            default: return nil
            }
        }

        /// The model preselected on first run and used as the fallback when the
        /// stored setting is unknown.
        static let recommended: ModelSize = .turboQ5

        /// Relative quality on a five-step scale, for the bar in ModelRow.
        /// Ordered with the catalogue: lighter models first.
        var qualitySteps: Int {
            switch self {
            case .base:    return 2
            case .small:   return 3
            case .turboQ5: return 4
            case .turboQ8: return 5
            case .turbo:   return 5
            }
        }
    }

    nonisolated static let modelsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("SayVoice/Models")
    }()

    func modelURL(for size: ModelSize) -> URL {
        Self.modelsDirectory.appendingPathComponent(size.fileName)
    }

    func isModelAvailable(_ size: ModelSize) -> Bool {
        FileManager.default.fileExists(atPath: modelURL(for: size).path)
    }

    /// Streams byte-level progress. Cancelling the consuming task stops the
    /// transfer and removes the partial file; the stream then simply finishes
    /// (iteration returns `nil`), so completion must be confirmed with
    /// `isModelAvailable(_:)` rather than inferred from the stream ending.
    func downloadModelProgress(_ size: ModelSize) -> AsyncThrowingStream<ModelDownloadProgress, Error> {
        let directory = Self.modelsDirectory
        let fileName = size.fileName
        let url = size.downloadURL

        return AsyncThrowingStream { continuation in
            let worker = Task.detached {
                let tempURL = directory.appendingPathComponent(fileName + ".tmp")
                let finalURL = directory.appendingPathComponent(fileName)
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

                    let (bytes, response) = try await URLSession.shared.bytes(from: url)
                    let totalBytes = response.expectedContentLength

                    if FileManager.default.fileExists(atPath: tempURL.path) {
                        try FileManager.default.removeItem(at: tempURL)
                    }
                    FileManager.default.createFile(atPath: tempURL.path, contents: nil)
                    let handle = try FileHandle(forWritingTo: tempURL)
                    defer { try? handle.close() }

                    var received: Int64 = 0
                    var chunk = Data()
                    chunk.reserveCapacity(65_536)

                    for try await byte in bytes {
                        // URLSession.AsyncBytes throws CancellationError here once the
                        // task is cancelled, which is what ends the stream promptly.
                        chunk.append(byte)
                        received += 1
                        if chunk.count >= 65_536 {
                            try handle.write(contentsOf: chunk)
                            chunk.removeAll(keepingCapacity: true)
                            continuation.yield(ModelDownloadProgress(bytesReceived: received, totalBytes: totalBytes))
                        }
                    }
                    if !chunk.isEmpty { try handle.write(contentsOf: chunk) }

                    if FileManager.default.fileExists(atPath: finalURL.path) {
                        try FileManager.default.removeItem(at: finalURL)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: finalURL)
                    continuation.yield(ModelDownloadProgress(bytesReceived: received, totalBytes: max(totalBytes, received)))
                    continuation.finish()
                    print("[SayVoice] Model downloaded: \(finalURL.path)")
                } catch {
                    try? FileManager.default.removeItem(at: tempURL)
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }

    /// Fraction-only view of `downloadModelProgress`, kept for the onboarding
    /// step until Phase 3 replaces it. It inherits the same caveat: a cancelled
    /// consumer sees the stream finish rather than throw, so confirm completion
    /// with `isModelAvailable(_:)`.
    func downloadModel(_ size: ModelSize) -> AsyncThrowingStream<Double, Error> {
        let source = downloadModelProgress(size)
        return AsyncThrowingStream { continuation in
            let relay = Task {
                do {
                    for try await p in source { continuation.yield(p.fraction) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in relay.cancel() }
        }
    }
}
