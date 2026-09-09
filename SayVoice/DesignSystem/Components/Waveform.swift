import SwiftUI

/// Live level bars, mirrored below a centre line. Bars stay in place and move
/// up and down; each bar has its own character (sensitivity and wobble), a
/// fast rise and a slow fall, and the level ripples from the centre outwards.
/// One `Canvas`, one draw pass per frame.
struct Waveform: View {
    let levels: [Float]
    var bars: Int = 24
    var tint: Color

    @State private var engine = BarEngine()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let spacing: CGFloat = 3

    init(levels: [Float], bars: Int = 24, tint: Color) {
        self.levels = levels
        self.bars = bars
        self.tint = tint
    }

    var body: some View {
        // Two schedules, two TimelineViews: `.animation` and `.periodic` are
        // distinct types, so they cannot be chosen by a ternary.
        Group {
            if reduceMotion {
                TimelineView(.periodic(from: .now, by: 1.0 / 15)) { canvas(at: $0.date) }
            } else {
                TimelineView(.animation) { canvas(at: $0.date) }
            }
        }
        .accessibilityHidden(true)
    }

    private func canvas(at date: Date) -> some View {
        Canvas { ctx, size in
            let now = date.timeIntervalSinceReferenceDate
            engine.step(now: now, history: levels, barCount: bars)

            let slot = size.width / CGFloat(bars)
            let barWidth = max(2, slot - spacing)
            let axisY = size.height / 2
            let maxHalf = axisY - 2

            var reflection = ctx
            reflection.opacity = 0.32

            for k in 0..<bars {
                let h = min(maxHalf, max(2, engine.heights[k] * maxHalf))
                let x = CGFloat(k) * slot + spacing / 2
                let radius = min(barWidth / 2, h / 2)

                ctx.fill(
                    Path(roundedRect: CGRect(x: x, y: axisY - h, width: barWidth, height: h), cornerRadius: radius),
                    with: .color(tint)
                )
                let mh = h * 0.55
                reflection.fill(
                    Path(roundedRect: CGRect(x: x, y: axisY + 2, width: barWidth, height: mh), cornerRadius: min(radius, mh / 2)),
                    with: .color(tint)
                )
            }
        }
    }
}

/// Per-bar heights with attack/decay smoothing. A plain class on purpose:
/// the Canvas is redrawn by TimelineView, and mutations during drawing must
/// not invalidate the view.
final class BarEngine {
    private(set) var heights: [CGFloat] = []
    private var lastTime: TimeInterval = 0

    /// Deterministic per-bar "character" (pseudo-random hash).
    private static func hash(_ k: Int) -> CGFloat {
        let s = sin(CGFloat(k) * 12.9898) * 43758.5453
        return s - s.rounded(.down)
    }

    func step(now: TimeInterval, history: [Float], barCount: Int) {
        if heights.count != barCount {
            heights = Array(repeating: 0, count: barCount)
            lastTime = now
        }
        let dt = min(0.1, max(0.001, now - lastTime))
        lastTime = now

        let center = CGFloat(barCount - 1) / 2

        for k in 0..<barCount {
            let hashK = Self.hash(k)
            let distance = abs(CGFloat(k) - center)

            // Ripple: outer bars react with a small delay (~40 Hz history)
            let delay = Int(distance * 0.9)
            let idx = history.count - 1 - delay
            let raw: CGFloat = (idx >= 0 && idx < history.count) ? CGFloat(history[idx]) : 0

            // Individuality: sensitivity plus a private wobble whose amplitude grows with volume
            let sensitivity = 0.7 + 0.3 * hashK
            let wobble = 0.72 + 0.28 * sin(now * (2.6 + 3.2 * Double(hashK)) + Double(k) * 1.7)
            let level = pow(min(1, raw), 1.15)
            let target = min(1, level * sensitivity * wobble * 1.5)

            // Fast rise, slow fall — classic VU dynamics
            let rate: CGFloat = target > heights[k] ? 24 : 9
            let alpha = 1 - exp(-dt * rate)
            heights[k] += (target - heights[k]) * alpha
        }
    }
}
