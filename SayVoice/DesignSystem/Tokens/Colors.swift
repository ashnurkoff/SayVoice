import AppKit
import SwiftUI

/// Namespace for the design system: tokens and shared helpers.
/// Components live in `DesignSystem/Components` and use only these tokens.
enum DS {}

/// A colour with one value per appearance. Stored as plain numbers so the
/// value is `Sendable` and safe as a global constant under strict
/// concurrency; the `NSColor` is built on access, which is cheap.
struct DSColor: Sendable {
    let darkHex: UInt32
    let darkAlpha: Double
    let lightHex: UInt32
    let lightAlpha: Double

    init(dark: UInt32, light: UInt32, darkAlpha: Double = 1, lightAlpha: Double = 1) {
        self.darkHex = dark
        self.darkAlpha = darkAlpha
        self.lightHex = light
        self.lightAlpha = lightAlpha
    }

    /// Dynamic colour that follows the effective appearance of the view it is drawn in.
    var nsColor: NSColor {
        let dark = Self.make(darkHex, darkAlpha)
        let light = Self.make(lightHex, lightAlpha)
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    var color: Color { Color(nsColor: nsColor) }

    /// Concrete colour for a given appearance — for tests and for AppKit
    /// drawing code that resolves colours itself (status icons).
    func resolved(for appearance: NSAppearance) -> NSColor {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? Self.make(darkHex, darkAlpha)
            : Self.make(lightHex, lightAlpha)
    }

    private static func make(_ hex: UInt32, _ alpha: Double) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension DS {
    /// Colour roles. Values come from the design spec §3.1; components never
    /// use literals, only these roles.
    enum Colors {
        // Grounds and surfaces
        static let ground   = DSColor(dark: 0x17171D, light: 0xF7F7FB)
        static let surface  = DSColor(dark: 0x202029, light: 0xFFFFFF)
        static let surface2 = DSColor(dark: 0x282833, light: 0xF2F2F8)
        static let line     = DSColor(dark: 0xFFFFFF, light: 0x000000, darkAlpha: 0.07, lightAlpha: 0.08)

        // Exactly three text levels
        static let text  = DSColor(dark: 0xF1F1F6, light: 0x191A22)
        static let muted = DSColor(dark: 0x9E9FB0, light: 0x6A6C80)
        static let faint = DSColor(dark: 0x64667A, light: 0xA7A9BA)

        // Brand — see the three-places rule in the spec
        static let accent     = DSColor(dark: 0x7B7FF2, light: 0x5B5FD6)
        static let accent2    = DSColor(dark: 0xA78BFA, light: 0x8B5CF6)
        static let accentSoft = DSColor(dark: 0x7B7FF2, light: 0x5B5FD6, darkAlpha: 0.16, lightAlpha: 0.12)

        // Semantic — separate from the accent
        static let rec  = DSColor(dark: 0xF5636F, light: 0xE8465A)
        static let ok   = DSColor(dark: 0x3ECF8E, light: 0x22A86B)
        static let warn = DSColor(dark: 0xE0A34A, light: 0xC4842A)

        // Glass (overlay)
        static let glassFill      = DSColor(dark: 0x202029, light: 0xFFFFFF, darkAlpha: 0.62, lightAlpha: 0.62)
        static let glassLine      = DSColor(dark: 0x7B7FF2, light: 0x5B5FD6, darkAlpha: 0.28, lightAlpha: 0.30)
        static let glassHighlight = DSColor(dark: 0xFFFFFF, light: 0xFFFFFF, darkAlpha: 0.22, lightAlpha: 0.95)
        // Overlay drop shadow: indigo-tinted on dark, plain on light
        static let glassShadow    = DSColor(dark: 0x281E78, light: 0x000000, darkAlpha: 0.35, lightAlpha: 0.18)
        /// Settings card drop shadow — much shallower than the overlay's, and
        /// neutral in both appearances.
        static let cardShadow     = DSColor(dark: 0x000000, light: 0x000000, darkAlpha: 0.12, lightAlpha: 0.12)

        // Orb gradient highlights — the lit top of the sphere for each
        // semantic state. Same value in both appearances: the orb is a light
        // source, not a surface, so it does not flip with the background.
        static let recHighlight  = DSColor(dark: 0xFF8A8A, light: 0xFF8A8A)
        static let okHighlight   = DSColor(dark: 0x8CEDB8, light: 0x8CEDB8)
        static let warnHighlight = DSColor(dark: 0xF7C773, light: 0xF7C773)
    }
}
