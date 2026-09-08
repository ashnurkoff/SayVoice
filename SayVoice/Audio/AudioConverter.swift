@preconcurrency import AVFAudio

/// Конвертирует AVAudioPCMBuffer из любого формата в 16kHz mono Float32 для whisper.cpp.
/// Помечен @unchecked Sendable т.к. используется только последовательно из audio tap callback.
final class AudioConverter: @unchecked Sendable {

    static let whisperFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    private let converter: AVAudioConverter
    private let inputFormat: AVAudioFormat

    // High-pass filter state (80 Hz cutoff, removes fan/AC hum)
    private var hpPrev: Float = 0
    private var hpOut: Float = 0
    private let hpAlpha: Float // coefficient based on cutoff / sample rate

    init(inputFormat: AVAudioFormat) throws {
        guard let conv = AVAudioConverter(from: inputFormat, to: Self.whisperFormat) else {
            throw AudioError.formatConversionFailed
        }
        self.converter = conv
        self.inputFormat = inputFormat

        // RC high-pass: alpha = RC / (RC + dt), cutoff = 80 Hz
        let cutoff: Float = 80.0
        let dt: Float = 1.0 / Float(Self.whisperFormat.sampleRate)
        let rc: Float = 1.0 / (2.0 * .pi * cutoff)
        self.hpAlpha = rc / (rc + dt)
    }

    func convert(_ inputBuffer: AVAudioPCMBuffer) throws -> [Float] {
        let ratio = Self.whisperFormat.sampleRate / inputFormat.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio) + 1

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: Self.whisperFormat,
            frameCapacity: outputFrameCapacity
        ) else {
            throw AudioError.formatConversionFailed
        }

        var conversionError: NSError?
        nonisolated(unsafe) var inputConsumed = false

        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if status == .error {
            throw AudioError.formatConversionFailed
        }

        guard let channelData = outputBuffer.floatChannelData?[0] else {
            throw AudioError.formatConversionFailed
        }

        let frameCount = Int(outputBuffer.frameLength)
        var samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

        // Apply high-pass filter to remove low-frequency noise
        applyHighPass(&samples)

        return samples
    }

    /// Single-pole RC high-pass filter (80 Hz cutoff).
    /// Removes DC offset, fan hum, AC buzz — keeps speech intact.
    private func applyHighPass(_ samples: inout [Float]) {
        for i in 0..<samples.count {
            let x = samples[i]
            hpOut = hpAlpha * (hpOut + x - hpPrev)
            hpPrev = x
            samples[i] = hpOut
        }
    }
}
