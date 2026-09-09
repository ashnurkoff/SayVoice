import XCTest
@testable import SayVoice

/// Whisper hallucinates on near-empty audio (it echoes the initial prompt),
/// so recordings without real speech must be rejected before transcription.
final class SilenceTrimmerTests: XCTestCase {
    private let rate = 16_000

    func testPureSilenceIsRejected() {
        XCTAssertNil(SilenceTrimmer.trim([Float](repeating: 0, count: rate * 7)))
    }

    func testQuietNoiseIsRejected() {
        var g = SeededGenerator(seed: 42)
        let noise = (0..<(rate * 7)).map { _ in Float.random(in: -0.002...0.002, using: &g) }
        XCTAssertNil(SilenceTrimmer.trim(noise))
    }

    func testSingleClickInSilenceIsRejected() {
        var s = [Float](repeating: 0, count: rate * 7)
        var g = SeededGenerator(seed: 42)
        for i in rate..<(rate + 300) { s[i] = Float.random(in: -0.4...0.4, using: &g) }   // ~19 ms click
        XCTAssertNil(SilenceTrimmer.trim(s), "one loud frame used to count as speech")
    }

    func testShortRealPhraseSurvives() {
        var g = SeededGenerator(seed: 42)
        var s = [Float](repeating: 0, count: rate * 3)
        let start = rate / 2
        for i in start..<(start + Int(0.6 * Double(rate))) {
            s[i] = 0.08 * sin(Float(i) * 0.05) + Float.random(in: -0.02...0.02, using: &g)
        }
        XCTAssertNotNil(SilenceTrimmer.trim(s), "0.6 s of speech must not be dropped")
    }

    func testTrimKeepsPaddingAroundSpeech() {
        var s = [Float](repeating: 0, count: rate * 4)
        for i in rate..<(rate * 2) { s[i] = 0.1 * sin(Float(i) * 0.03) }
        let t = SilenceTrimmer.trim(s)!
        XCTAssertLessThan(t.count, s.count)
        XCTAssertGreaterThan(t.count, rate)              // speech plus padding
        XCTAssertLessThan(t.count, rate + 2 * 8 * 480 + 480)  // not more than pad on each side
    }
}

/// A seeded generator, so the noise these tests build is the same on every
/// run. The trimmer's thresholds sit close to the levels used here, and a
/// test that fails once a month is worse than no test at all.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    }

    /// splitmix64 — small, fast, and good enough for test fixtures.
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
