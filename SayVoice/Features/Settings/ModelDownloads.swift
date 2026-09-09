import Foundation

/// Turns `ModelManager`'s byte stream into `DownloadState`s the UI renders,
/// one per model, and owns the running tasks so Cancel actually cancels.
@MainActor @Observable
final class ModelDownloads {
    private let progressSource: @MainActor (ModelManager.ModelSize) -> AsyncThrowingStream<ModelDownloadProgress, Error>
    private let isAvailable: @MainActor (ModelManager.ModelSize) -> Bool
    private var states: [ModelManager.ModelSize: DownloadState] = [:]
    private var tasks: [ModelManager.ModelSize: Task<Void, Never>] = [:]
    /// Bumped by every start and every cancel. A run whose generation is no
    /// longer the current one has been superseded and may not touch the state.
    private var generations: [ModelManager.ModelSize: Int] = [:]

    /// Called when a download finishes successfully.
    var onCompleted: ((ModelManager.ModelSize) -> Void)?

    /// The two closures default to `modelManager`; tests inject stubs to drive
    /// the state machine without a network transfer. (Swift cannot spell that
    /// default in the parameter list, since it derives from another parameter,
    /// hence the optionals.)
    init(
        modelManager: ModelManager,
        progressSource: (@MainActor (ModelManager.ModelSize) -> AsyncThrowingStream<ModelDownloadProgress, Error>)? = nil,
        isAvailable: (@MainActor (ModelManager.ModelSize) -> Bool)? = nil
    ) {
        self.progressSource = progressSource ?? { modelManager.downloadModelProgress($0) }
        self.isAvailable = isAvailable ?? { modelManager.isModelAvailable($0) }
    }

    /// `nil` when the model is already on disk (nothing to offer),
    /// `.idle` when it can be downloaded, otherwise the live state.
    ///
    /// `.done` is transient — once the file is on disk this returns `nil`, so
    /// the settings list never renders the done state; the row shows its
    /// downloaded chip instead.
    func state(for size: ModelManager.ModelSize) -> DownloadState? {
        if isAvailable(size) { return nil }
        return states[size] ?? .idle
    }

    #if DEBUG
    /// Test hook: the stored state, before `state(for:)` hides it behind the
    /// on-disk check.
    func storedState(for size: ModelManager.ModelSize) -> DownloadState? { states[size] }
    #endif

    /// Longest span of samples the speed is averaged over.
    private static let rateWindow: TimeInterval = 2
    /// Shortest span that gives a speed worth showing.
    private static let minimumRateSpan: TimeInterval = 0.5
    /// Ten state writes a second are plenty; more only makes the label flicker.
    private static let writeInterval: TimeInterval = 0.1

    func start(_ size: ModelManager.ModelSize) {
        guard tasks[size] == nil else { return }
        let generation = (generations[size] ?? 0) + 1
        generations[size] = generation
        states[size] = .running(fraction: 0, bytesPerSecond: nil, secondsLeft: nil)
        tasks[size] = Task { [self] in
            // The speed is averaged over a rolling window rather than the last
            // two samples, so one slow chunk does not halve the number on screen.
            var window: [(bytes: Int64, at: TimeInterval)] = []
            var lastWrite: TimeInterval = 0
            var outcome: (cancelled: Bool, message: String?)
            do {
                for try await p in progressSource(size) {
                    let now = Date().timeIntervalSinceReferenceDate
                    window.append((p.bytesReceived, now))
                    while window.count > 1, now - window[0].at > Self.rateWindow { window.removeFirst() }
                    let baseline = now - window[0].at >= Self.minimumRateSpan ? window[0] : nil
                    let (speed, eta) = Self.rate(previous: baseline, current: (p.bytesReceived, now), total: p.totalBytes)

                    // Cancel has already shown the row as idle; a yield still in
                    // flight must not put it back into running.
                    guard !Task.isCancelled else { continue }
                    guard now - lastWrite >= Self.writeInterval else { continue }
                    lastWrite = now
                    states[size] = .running(fraction: p.fraction, bytesPerSecond: speed, secondsLeft: eta)
                }
                outcome = (cancelled: false, message: nil)
            } catch is CancellationError {
                outcome = (cancelled: true, message: nil)
            } catch {
                // The transfer's cancellation error type is not contractual —
                // URLSession surfaces `URLError(.cancelled)` — so cancellation
                // is decided by the task, not by the error.
                outcome = (cancelled: false, message: error.localizedDescription)
            }
            // Cancel freed the slot at once and a retry may already be running:
            // this run's outcome belongs to a transfer that is over, so it must
            // touch neither the state nor the slot.
            guard generations[size] == generation else { return }
            settle(size, cancelled: outcome.cancelled, message: outcome.message)
            tasks[size] = nil
        }
    }

    func cancel(_ size: ModelManager.ModelSize) {
        guard let task = tasks[size] else { return }
        // Free the slot before cancelling, so the next Retry starts at once
        // instead of waiting for the transfer to unwind; the generation bump
        // makes the unwinding run ignore its own outcome.
        tasks[size] = nil
        generations[size] = (generations[size] ?? 0) + 1
        task.cancel()
        // Show it at once — the transfer unwinds a moment later.
        states[size] = .idle
    }

    /// The one place a finished transfer's final state is decided, always in
    /// this order. A cancelled consumer sees the stream simply finish rather
    /// than throw, so success is confirmed on disk — never inferred from the
    /// stream ending; and the file wins over cancellation, because a transfer
    /// that completed just as Cancel was pressed did produce a usable model.
    private func settle(_ size: ModelManager.ModelSize, cancelled: Bool, message: String?) {
        if isAvailable(size) {
            states[size] = .done
            onCompleted?(size)
        } else if cancelled || Task.isCancelled {
            states[size] = .idle
        } else {
            states[size] = .failed(message ?? "Download did not complete.")
        }
    }

    /// Bytes per second and seconds left from two samples — `previous` is the
    /// oldest sample still inside the rolling window. Both are nil without a
    /// baseline; the time left is nil on its own when the total is unknown or
    /// already reached.
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
