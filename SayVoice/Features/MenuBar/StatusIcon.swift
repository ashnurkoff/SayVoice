import AppKit

/// Menu-bar icon per state. Idle and error are template glyphs (the system
/// tints them); recording and transcribing draw a coloured dot, so they are
/// not templates. No animation: the menu bar speaks the orb's state language.
enum StatusIcon {
    private static let pointSize: CGFloat = 16

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

    private static func glyph(_ name: String, description: String) -> NSImage {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: description)!
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .regular))!
        img.isTemplate = true
        return img
    }

    private static func micWithDot(_ dot: NSColor, description: String) -> NSImage {
        let size = NSSize(width: 21, height: 21)
        let img = NSImage(size: size, flipped: false) { rect in
            let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
                .applying(.init(paletteColors: [.labelColor]))
            if let mic = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                let origin = NSPoint(x: (rect.width - mic.size.width) / 2, y: (rect.height - mic.size.height) / 2)
                mic.draw(in: NSRect(origin: origin, size: mic.size))
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
}
