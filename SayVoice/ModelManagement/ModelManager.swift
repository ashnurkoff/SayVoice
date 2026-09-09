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

        /// Sizes checked against the HuggingFace API (decimal MB, as in Finder).
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

        /// One line under the name in the model list, in both Settings and
        /// onboarding: what this model is actually for. The catalogue is the
        /// only place that knows; `ModelRow` renders whatever it is handed.
        var purpose: String {
            switch self {
            case .base:    return "Fastest and roughest; short English commands only."
            case .small:   return "Light and quick; fine for English, weak on Russian."
            case .turboQ5: return "Best balance: accurate in Russian and English, faster than real time."
            case .turboQ8: return "Same model, less compression; marginally more accurate for 300 MB more."
            case .turbo:   return "Full precision; no audible gain over Q8 on Apple Silicon, 1.6 GB."
            }
        }

        var fileName: String { "\(rawValue).bin" }

        var downloadURL: URL {
            URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
        }

        /// The string stored in UserDefaults (see SettingsStore.modelSize).
        var settingsString: String {
            switch self {
            case .base:    return "base"
            case .small:   return "small"
            case .turboQ5: return "large-v3-turbo-q5"
            case .turboQ8: return "large-v3-turbo-q8"
            case .turbo:   return "large-v3-turbo"
            }
        }

        /// Converts the settings string into the enum.
        /// Tiny is gone from the list: it turns Russian speech into mush, and
        /// its speed is not needed on Apple Silicon — Turbo Q5 transcribes
        /// faster than real time. A stored choice of "tiny" is moved to the
        /// nearest one left, Base.
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

    /// Configuration of the download session. Tests inject one carrying a
    /// `URLProtocol` stub so the transfer path can be exercised offline.
    private let sessionConfiguration: URLSessionConfiguration

    init(modelsDirectory: URL = ModelManager.defaultModelsDirectory,
         sessionConfiguration: URLSessionConfiguration = .default) {
        self.modelsDirectory = modelsDirectory
        self.sessionConfiguration = sessionConfiguration
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
        let configuration = sessionConfiguration

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
            let session = URLSession(configuration: configuration, delegate: relay, delegateQueue: nil)
            let task = session.downloadTask(with: url)
            relay.adopt(session: session, task: task)
            continuation.onTermination = { [relay] _ in relay.cancelAndInvalidate() }
            task.resume()
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
        // A 404 or a 500 is a perfectly successful transfer whose body is an
        // error page. Checked before anything is touched on disk, so a failed
        // retry cannot delete the model that is already installed.
        if let http = downloadTask.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            continuation.finish(throwing: URLError(.badServerResponse))
            return
        }
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
