import AppKit

/// Menu-bar icon per state. Idle and error are template glyphs (the system
/// tints them); recording and transcribing draw a coloured dot, so they are
/// not templates. Every state is drawn on the same canvas, so the status item
/// keeps its width as the state changes. No animation: the menu bar speaks the
/// orb's state language.
enum StatusIcon {
    private static let pointSize: CGFloat = 16
    /// Shared canvas for every state — see the note above.
    static let canvas = NSSize(width: 21, height: 21)

    @MainActor
    static func image(for state: AppState, appearance: NSAppearance) -> NSImage {
        switch state {
        case .idle:
            return mark(description: "SayVoice")
        case .recording:
            return markWithDot(DS.Colors.rec.resolved(for: appearance), description: "Recording")
        case .transcribing, .injecting:
            return markWithDot(DS.Colors.accent.resolved(for: appearance), description: "Transcribing")
        case .error:
            return glyph("exclamationmark.triangle", description: "Needs attention")
        }
    }

    /// A glyph on its own. Drawn without a palette, so only its alpha carries
    /// shape, and marked as a template — the menu bar tints it.
    private static func glyph(_ name: String, description: String) -> NSImage {
        let img = NSImage(size: canvas, flipped: false) { rect in
            if let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: pointSize, weight: .regular)) {
                draw(symbol, centeredIn: rect)
            }
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = description
        return img
    }

    /// The brand waveform sized like a 16 pt symbol, centred on the canvas.
    private static var markRect: NSRect {
        let width: CGFloat = 17
        let height = width / WaveformMark.aspect
        return NSRect(x: (canvas.width - width) / 2, y: (canvas.height - height) / 2, width: width, height: height)
    }

    /// The waveform on its own, as a template — the menu bar tints it.
    private static func mark(description: String) -> NSImage {
        let img = NSImage(size: canvas, flipped: false) { _ in
            NSColor.black.setFill()
            WaveformMark.bezierPath(in: markRect).fill()
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = description
        return img
    }

    /// The waveform plus a coloured state dot. Not a template: template
    /// rendering is monochrome and would swallow the dot's colour.
    private static func markWithDot(_ dot: NSColor, description: String) -> NSImage {
        let img = NSImage(size: canvas, flipped: false) { rect in
            // labelColor is dynamic — white on a dark menu bar, black on a light one
            NSColor.labelColor.setFill()
            WaveformMark.bezierPath(in: markRect).fill()
            let d: CGFloat = 6.5
            dot.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.maxX - d, y: rect.maxY - d, width: d, height: d)).fill()
            return true
        }
        img.isTemplate = false
        img.accessibilityDescription = description
        return img
    }

    private static func draw(_ symbol: NSImage, centeredIn rect: NSRect) {
        let origin = NSPoint(x: (rect.width - symbol.size.width) / 2, y: (rect.height - symbol.size.height) / 2)
        symbol.draw(in: NSRect(origin: origin, size: symbol.size))
    }
}
