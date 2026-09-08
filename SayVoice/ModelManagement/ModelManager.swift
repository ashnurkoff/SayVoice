import Foundation

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

    func downloadModel(_ size: ModelSize) -> AsyncThrowingStream<Double, Error> {
        AsyncThrowingStream { continuation in
            Task.detached {
                do {
                    try FileManager.default.createDirectory(
                        at: Self.modelsDirectory,
                        withIntermediateDirectories: true
                    )

                    let (bytes, response) = try await URLSession.shared.bytes(from: size.downloadURL)
                    let totalBytes = response.expectedContentLength

                    let tempURL = Self.modelsDirectory.appendingPathComponent(size.fileName + ".tmp")
                    if FileManager.default.fileExists(atPath: tempURL.path) {
                        try FileManager.default.removeItem(at: tempURL)
                    }
                    FileManager.default.createFile(atPath: tempURL.path, contents: nil)

                    let handle = try FileHandle(forWritingTo: tempURL)
                    defer { try? handle.close() }

                    var downloadedBytes: Int64 = 0
                    var chunk = Data()
                    chunk.reserveCapacity(65536)

                    for try await byte in bytes {
                        chunk.append(byte)
                        downloadedBytes += 1

                        if chunk.count >= 65536 {
                            try handle.write(contentsOf: chunk)
                            chunk.removeAll(keepingCapacity: true)

                            if totalBytes > 0 {
                                continuation.yield(Double(downloadedBytes) / Double(totalBytes))
                            }
                        }
                    }

                    if !chunk.isEmpty {
                        try handle.write(contentsOf: chunk)
                    }

                    let finalURL = Self.modelsDirectory.appendingPathComponent(size.fileName)
                    if FileManager.default.fileExists(atPath: finalURL.path) {
                        try FileManager.default.removeItem(at: finalURL)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: finalURL)

                    continuation.yield(1.0)
                    continuation.finish()
                    print("[SayVoice] Model downloaded: \(finalURL.path)")
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
