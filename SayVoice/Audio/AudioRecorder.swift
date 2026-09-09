import AVFAudio
import os

actor AudioRecorder {

    private let engine = AVAudioEngine()
    private var audioConverter: AudioConverter?
    private var isCapturing = false

    // pcmBuffer is written from the real-time audio thread (appendBufferSync)
    // and read in stopCapture. Writing used to go through
    // `Task { await append(...) }` — asynchronously: the last buffers did not
    // make it in before stopCapture read them (the tail of the recording was
    // lost — "the last sentence got cut off"), and the order was not guaranteed
    // either. The buffer now sits under an OSAllocatedUnfairLock: writes and
    // reads are synchronous through withLock (async-safe for Swift 6), so the
    // tail is guaranteed to reach the result.
    private let pcmBuffer = OSAllocatedUnfairLock<[Float]>(initialState: [])

    // MARK: - Public

    func startCapture(onLevel: (@Sendable (Float) -> Void)? = nil) async throws {
        guard !isCapturing else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        guard inputFormat.channelCount > 0 else {
            throw AudioError.noAudioInput
        }

        print("[SayVoice] Mic input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch, \(inputFormat.commonFormat.rawValue == 3 ? "Float32" : "other(\(inputFormat.commonFormat.rawValue))")")

        let converter = try AudioConverter(inputFormat: inputFormat)
        self.audioConverter = converter
        pcmBuffer.withLock { buffer in
            buffer.removeAll(keepingCapacity: true)
            buffer.reserveCapacity(16_000 * 30) // 30 sec reserve
        }

        let levelHandler = onLevel

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            // Real-time audio thread: convert and write into the buffer
            // synchronously under the unfair lock (no async hop), so the last
            // buffers are not lost.
            guard let self else { return }
            self.appendBufferSync(buffer, converter: converter, onLevel: levelHandler)
        }

        do {
            try engine.start()
            isCapturing = true
        } catch {
            inputNode.removeTap(onBus: 0)
            throw AudioError.engineStartFailed(error)
        }
    }

    func stopCapture() -> [Float] {
        guard isCapturing else { return [] }
        // Remove the tap and stop the engine first — no new callbacks arrive
        // after that. Any appendBufferSync already running holds the unfair
        // lock, so the read below waits for it to finish: the tail of the
        // recording is guaranteed to reach the result.
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false
        return pcmBuffer.withLock { buffer -> [Float] in
            let captured = buffer
            buffer = []
            return captured
        }
    }

    // MARK: - Private

    /// Called from real-time audio thread. Only lock-free ops.
    nonisolated private func appendBufferSync(
        _ buffer: AVAudioPCMBuffer,
        converter: AudioConverter,
        onLevel: (@Sendable (Float) -> Void)?
    ) {
        guard let converted = try? converter.convert(buffer) else { return }

        if let onLevel {
            // 4 sub-measurements per buffer (~40 Hz instead of ~12): the
            // waveform catches the transients of speech rather than a level
            // averaged over 85 ms.
            let chunkCount = 4
            let chunkSize = max(1, converted.count / chunkCount)
            var start = 0
            while start < converted.count {
                let end = min(start + chunkSize, converted.count)
                onLevel(Self.normalizedRMS(converted[start..<end]))
                start = end
            }
        }

        // A synchronous write under the lock — no async hop, or the last
        // buffers are lost when stopCapture reads the buffer before they land.
        pcmBuffer.withLock { $0.append(contentsOf: converted) }
    }

    /// Compute RMS and normalize to 0...1 visual range.
    nonisolated private static func normalizedRMS(_ samples: ArraySlice<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        let rms = sqrt(sumOfSquares / Float(samples.count))
        // Map dB range to 0...1 (-46 dB → 0, -14 dB → 1):
        // a narrower range makes the speech visualisation more contrasty
        let db = 20.0 * log10(max(rms, 0.00001))
        let normalized = (db + 46.0) / 32.0
        return max(0, min(1, normalized))
    }
}
