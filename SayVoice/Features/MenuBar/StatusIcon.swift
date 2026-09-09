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
            return glyph("mic.fill", description: "SayVoice")
        case .recording:
            return micWithDot(DS.Colors.rec.resolved(for: appearance), description: "Recording")
        case .transcribing, .injecting:
            return micWithDot(DS.Colors.accent.resolved(for: appearance), description: "Transcribing")
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

    /// The mic plus a coloured state dot. Not a template: template rendering is
    /// monochrome and would swallow the dot's colour.
    private static func micWithDot(_ dot: NSColor, description: String) -> NSImage {
        let img = NSImage(size: canvas, flipped: false) { rect in
            // labelColor is dynamic — white on a dark menu bar, black on a light one
            let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
                .applying(.init(paletteColors: [.labelColor]))
            if let mic = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                draw(mic, centeredIn: rect)
            }
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
