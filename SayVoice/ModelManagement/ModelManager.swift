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

    /// Where the app keeps its models. Tests inject a temporary directory so
    /// the suite never reads or writes the real one.
    nonisolated static let defaultModelsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("SayVoice/Models")
    }()

    let modelsDirectory: URL

    init(modelsDirectory: URL = ModelManager.defaultModelsDirectory) {
        self.modelsDirectory = modelsDirectory
    }

    func modelURL(for size: ModelSize) -> URL {
        modelsDirectory.appendingPathComponent(size.fileName)
    }

    func isModelAvailable(_ size: ModelSize) -> Bool {
        FileManager.default.fileExists(atPath: modelURL(for: size).path)
    }

    /// Streams byte-level progress of a `URLSessionDownloadTask`. Cancelling
    /// the consuming task stops the transfer and discards the partial file
    /// (URLSession never hands it over, so no model file is published); the
    /// stream then simply finishes (iteration returns `nil`), so completion
    /// must be confirmed with `isModelAvailable(_:)` rather than inferred from
    /// the stream ending.
    func downloadModelProgress(_ size: ModelSize) -> AsyncThrowingStream<ModelDownloadProgress, Error> {
        let directory = modelsDirectory
        let finalURL = modelURL(for: size)
        let url = size.downloadURL

        return AsyncThrowingStream { continuation in
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                continuation.finish(throwing: error)
                return
            }

            // URLSession owns the partial file: it writes to its own temp
            // location and hands it over only once the transfer completed, so
            // there is no half-written model to clean up after a cancel.
            let relay = DownloadRelay(finalURL: finalURL, continuation: continuation)
            let session = URLSession(configuration: .default, delegate: relay, delegateQueue: nil)
            let task = session.downloadTask(with: url)
            relay.adopt(session: session, task: task)
            continuation.onTermination = { [relay] _ in relay.cancelAndInvalidate() }
            task.resume()
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

// MARK: - Download delegate

/// Bridges `URLSessionDownloadTask` callbacks onto an `AsyncThrowingStream`.
///
/// A download task transfers on URLSession's own threads instead of one byte
/// at a time through Swift concurrency, which is what keeps a model download
/// network-bound. State is touched only from the session's serial delegate
/// queue and from `cancelAndInvalidate`, hence `@unchecked Sendable`.
private final class DownloadRelay: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let finalURL: URL
    private let continuation: AsyncThrowingStream<ModelDownloadProgress, Error>.Continuation
    private let lock = NSLock()
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var received: Int64 = 0
    private var expected: Int64 = 0

    init(finalURL: URL, continuation: AsyncThrowingStream<ModelDownloadProgress, Error>.Continuation) {
        self.finalURL = finalURL
        self.continuation = continuation
    }

    /// The relay holds the session and the task so the stream's termination
    /// handler needs to capture nothing but the relay itself.
    func adopt(session: URLSession, task: URLSessionDownloadTask) {
        lock.lock()
        self.session = session
        self.task = task
        lock.unlock()
    }

    /// Called once the stream ends, whether it finished or the consumer went
    /// away. Cancelling a finished task is a no-op.
    func cancelAndInvalidate() {
        lock.lock()
        let task = self.task
        let session = self.session
        self.task = nil
        self.session = nil
        lock.unlock()
        task?.cancel()
        session?.finishTasksAndInvalidate()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        received = totalBytesWritten
        expected = max(0, totalBytesExpectedToWrite)
        continuation.yield(ModelDownloadProgress(bytesReceived: received, totalBytes: expected))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The system deletes `location` as soon as this returns, so the move
        // has to happen here rather than on another queue.
        do {
            if FileManager.default.fileExists(atPath: finalURL.path) {
                try FileManager.default.removeItem(at: finalURL)
            }
            try FileManager.default.moveItem(at: location, to: finalURL)
            let size = Self.fileSize(of: finalURL) ?? received
            continuation.yield(ModelDownloadProgress(bytesReceived: size, totalBytes: max(expected, size)))
            continuation.finish()
            print("[SayVoice] Model downloaded: \(finalURL.path)")
        } catch {
            continuation.finish(throwing: error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else {
            // Success already finished the stream in didFinishDownloadingTo;
            // finishing twice is a no-op.
            continuation.finish()
            return
        }
        // A cancelled transfer surfaces as URLError.cancelled — the consumer
        // asked for it, so report it as cancellation.
        if (error as? URLError)?.code == .cancelled {
            continuation.finish(throwing: CancellationError())
        } else {
            continuation.finish(throwing: error)
        }
    }

    private static func fileSize(of url: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return (attributes[.size] as? NSNumber)?.int64Value
    }
}
