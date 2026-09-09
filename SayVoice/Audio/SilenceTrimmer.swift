import Foundation

/// Silence trimming and detection of "empty" recordings.
///
/// Whisper hallucinates on silence and on quiet audio: trained on YouTube
/// captions, it answers an empty input with cliches along the lines of "Thanks
/// for the subtitles…" / "Thank you for watching". A trailing pause at the end
/// of a long dictation does the same — the model fills the last window with a
/// cliche instead of the real text.
///
/// The fix, before whisper is reached:
///  - no speech at all → skip the transcription (insert nothing);
///  - otherwise cut the leading and trailing silence, keeping a little padding.
///
/// A pure function with no dependencies — tested apart from the application.
enum SilenceTrimmer {

    /// 16 kHz mono — the format the audio arrives in from AudioConverter.
    static let sampleRate = 16_000

    /// Frame length for the energy estimate: 30 ms.
    static let frameLength = 480

    /// Speech threshold on a frame's RMS. Room silence after the high-pass
    /// filter is ≈ −60…−50 dBFS, speech ≈ −35…−20 dBFS, quiet speech ≈ −42 dBFS.
    /// 0.005 ≈ −46 dBFS — conservative: it catches silence reliably and almost
    /// certainly never cuts real speech.
    static let speechRMSThreshold: Float = 0.005

    /// Padding around the speech, so quiet starts and ends of words are not clipped: ~240 ms.
    static let padFrames = 8

    /// How many frames must be speech for the recording to count as non-empty:
    /// 10 × 30 ms = 0.3 s.
    ///
    /// ONE frame above the threshold used to be enough — a knock on the desk or
    /// a button click passed for speech, and on such a recording whisper simply
    /// continued the initial_prompt: garbled scraps of the instruction landed in
    /// the history, along with the classic caption junk (the name of a Russian
    /// YouTube channel). In a real dictation more than half the frames are
    /// speech (measured: 62% on a 21-second recording), so the threshold has
    /// room to spare.
    static let minSpeechFrames = 10

    /// The range of samples that contain speech (with padding), or nil when there is none.
    static func speechRange(
        _ samples: [Float],
        frameLength: Int = frameLength,
        threshold: Float = speechRMSThreshold,
        padFrames: Int = padFrames,
        minSpeechFrames: Int = minSpeechFrames
    ) -> Range<Int>? {
        guard !samples.isEmpty, frameLength > 0 else { return nil }

        var firstSpeechFrame = -1
        var lastSpeechFrame = -1
        var speechFrames = 0
        var frameStart = 0
        var frameIndex = 0

        while frameStart < samples.count {
            let frameEnd = min(frameStart + frameLength, samples.count)
            var sumSquares: Float = 0
            var i = frameStart
            while i < frameEnd {
                let s = samples[i]
                sumSquares += s * s
                i += 1
            }
            let count = frameEnd - frameStart
            let rms = count > 0 ? (sumSquares / Float(count)).squareRoot() : 0
            if rms >= threshold {
                if firstSpeechFrame < 0 { firstSpeechFrame = frameIndex }
                lastSpeechFrame = frameIndex
                speechFrames += 1
            }
            frameStart = frameEnd
            frameIndex += 1
        }

        // No speech at all, or too little of it for this to be a dictation.
        guard firstSpeechFrame >= 0, speechFrames >= minSpeechFrames else { return nil }

        let start = max(0, (firstSpeechFrame - padFrames) * frameLength)
        let end = min(samples.count, (lastSpeechFrame + 1 + padFrames) * frameLength)
        return start..<end
    }

    /// Cuts the leading and trailing silence. Returns nil when there is no
    /// speech — the caller must then skip the transcription.
    static func trim(_ samples: [Float]) -> [Float]? {
        guard let range = speechRange(samples) else { return nil }
        if range.lowerBound == 0 && range.upperBound == samples.count {
            return samples
        }
        return Array(samples[range])
    }
}
