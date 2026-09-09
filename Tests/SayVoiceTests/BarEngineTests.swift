import XCTest
@testable import SayVoice

/// BarEngine smooths raw levels into bar heights: fast attack, slow decay,
/// with a small per-bar delay so the wave "ripples" from the centre.
final class BarEngineTests: XCTestCase {

    func testBarsRiseQuicklyOnLoudInput() {
        let e = BarEngine()
        var t: TimeInterval = 0
        let loud = [Float](repeating: 0.9, count: 64)
        for _ in 0..<6 { t += 1.0 / 60; e.step(now: t, history: loud, barCount: 24) }   // 100 ms
        XCTAssertGreaterThan(e.heights[12], 0.5, "centre bar should be well up after 100 ms of loud input")
    }

    func testBarsDecaySlowlyOnSilence() {
        let e = BarEngine()
        var t: TimeInterval = 0
        let loud = [Float](repeating: 0.9, count: 64)
        for _ in 0..<30 { t += 1.0 / 60; e.step(now: t, history: loud, barCount: 24) }
        let peak = e.heights[12]
        let quiet = [Float](repeating: 0, count: 64)
        for _ in 0..<3 { t += 1.0 / 60; e.step(now: t, history: quiet, barCount: 24) }   // 50 ms
        XCTAssertGreaterThan(e.heights[12], peak * 0.4, "decay must be visibly slower than attack")
        for _ in 0..<60 { t += 1.0 / 60; e.step(now: t, history: quiet, barCount: 24) }  // +1 s
        XCTAssertLessThan(e.heights[12], 0.05)
    }

    func testBarCountChangeResets() {
        let e = BarEngine()
        e.step(now: 1, history: [0.5], barCount: 8)
        XCTAssertEqual(e.heights.count, 8)
        e.step(now: 2, history: [0.5], barCount: 24)
        XCTAssertEqual(e.heights.count, 24)
    }
}
