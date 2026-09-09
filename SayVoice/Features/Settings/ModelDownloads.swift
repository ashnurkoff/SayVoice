import Foundation

/// Turns `ModelManager`'s byte stream into `DownloadState`s the UI renders,
/// one per model, and owns the running tasks so Cancel actually cancels.
@MainActor @Observable
final class ModelDownloads {
    private let modelManager: ModelManager
    private var states: [ModelManager.ModelSize: DownloadState] = [:]
    private var tasks: [ModelManager.ModelSize: Task<Void, Never>] = [:]

    /// Called when a download finishes successfully.
    var onCompleted: ((ModelManager.ModelSize) -> Void)?

    init(modelManager: ModelManager) {
        self.modelManager = modelManager
    }

    /// `nil` when the model is already on disk (nothing to offer),
    /// `.idle` when it can be downloaded, otherwise the live state.
    func state(for size: ModelManager.ModelSize) -> DownloadState? {
        if modelManager.isModelAvailable(size) { return nil }
        return states[size] ?? .idle
    }

    func start(_ size: ModelManager.ModelSize) {
        guard tasks[size] == nil else { return }
        states[size] = .running(fraction: 0, bytesPerSecond: nil, secondsLeft: nil)
        tasks[size] = Task { [self] in
            var previous: (bytes: Int64, at: TimeInterval)? = nil
            do {
                for try await p in modelManager.downloadModelProgress(size) {
                    let now = Date().timeIntervalSinceReferenceDate
                    let (speed, eta) = Self.rate(previous: previous, current: (p.bytesReceived, now), total: p.totalBytes)
                    // Sample the rate at most every half second so it does not flicker.
                    if previous == nil || now - previous!.at >= 0.5 {
                        previous = (p.bytesReceived, now)
                    }
                    states[size] = .running(fraction: p.fraction, bytesPerSecond: speed, secondsLeft: eta)
                }
                // A cancelled consumer sees the stream simply finish rather than
                // throw, so success is confirmed on disk — never inferred from
                // the stream ending.
                if Task.isCancelled {
                    states[size] = .idle
                } else if modelManager.isModelAvailable(size) {
                    states[size] = .done
                    onCompleted?(size)
                } else {
                    states[size] = .failed("Download did not complete.")
                }
            } catch is CancellationError {
                states[size] = .idle
            } catch {
                // The transfer's cancellation error type is not contractual —
                // URLSession surfaces `URLError(.cancelled)` — so cancellation
                // is decided by the task, not by the error.
                states[size] = Task.isCancelled ? .idle : .failed(error.localizedDescription)
            }
            tasks[size] = nil
        }
    }

    func cancel(_ size: ModelManager.ModelSize) {
        tasks[size]?.cancel()
    }

    /// Bytes per second and seconds left from two samples; nil until there
    /// are two samples or when the total is unknown.
    nonisolated static func rate(
        previous: (bytes: Int64, at: TimeInterval)?,
        current: (bytes: Int64, at: TimeInterval),
        total: Int64
    ) -> (Double?, Double?) {
        guard let previous, current.at > previous.at, current.bytes >= previous.bytes else { return (nil, nil) }
        let speed = Double(current.bytes - previous.bytes) / (current.at - previous.at)
        guard speed > 0, total > current.bytes else { return (speed > 0 ? speed : nil, nil) }
        return (speed, Double(total - current.bytes) / speed)
    }
}
