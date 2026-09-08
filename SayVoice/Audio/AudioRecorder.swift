import AVFAudio
import os

actor AudioRecorder {

    private let engine = AVAudioEngine()
    private var audioConverter: AudioConverter?
    private var isCapturing = false

    // pcmBuffer пишется из real-time аудио-потока (appendBufferSync) и читается из
    // stopCapture. Раньше запись шла через `Task { await append(...) }` — асинхронно:
    // последние буферы не успевали дозаписаться до чтения в stopCapture (терялся хвост
    // записи — «обрезалось последнее предложение»), плюс порядок не был гарантирован.
    // Теперь буфер под OSAllocatedUnfairLock: запись/чтение синхронны через withLock
    // (async-safe для Swift 6) — хвост гарантированно попадает в результат.
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
            // Real-time audio thread: конвертируем и пишем в буфер синхронно под
            // unfair-локом (без async-хопа), чтобы не терять последние буферы.
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
        // Сначала снимаем тап и останавливаем движок — новые колбэки больше не придут.
        // Любой уже выполняющийся appendBufferSync держит unfair-лок, поэтому чтение
        // ниже дождётся его завершения: хвост записи гарантированно попадёт в result.
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
            // 4 суб-замера на буфер (~40 Гц вместо ~12): эквалайзер ловит
            // транзиенты речи, а не усреднённый по 85 мс уровень.
            let chunkCount = 4
            let chunkSize = max(1, converted.count / chunkCount)
            var start = 0
            while start < converted.count {
                let end = min(start + chunkSize, converted.count)
                onLevel(Self.normalizedRMS(converted[start..<end]))
                start = end
            }
        }

        // Синхронная запись под локом — без async-хопа, иначе последние буферы
        // теряются, если stopCapture успевает прочитать буфер раньше их дозаписи.
        pcmBuffer.withLock { $0.append(contentsOf: converted) }
    }

    /// Compute RMS and normalize to 0...1 visual range.
    nonisolated private static func normalizedRMS(_ samples: ArraySlice<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        let rms = sqrt(sumOfSquares / Float(samples.count))
        // Map dB range to 0...1 (-46 dB → 0, -14 dB → 1):
        // уже диапазон = контрастнее визуализация речи
        let db = 20.0 * log10(max(rms, 0.00001))
        let normalized = (db + 46.0) / 32.0
        return max(0, min(1, normalized))
    }
}
