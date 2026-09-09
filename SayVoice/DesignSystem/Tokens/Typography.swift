import CoreText
import SwiftUI

extension DS {
    /// Text styles from the design spec §3.2. Sizes and weights are fixed here
    /// so screens never pick their own.
    enum TextStyle {
        case display      // 24 / 700  onboarding step title
        case section      // 22 / 700  settings section title
        case title        // 17 / 600  card title, popover header
        case bodyLarge    // 15 / 500  overlay result, primary labels
        case body         // 13 / 400
        case bodyMedium   // 13 / 500
        case caption      // 12 / 400  explanatory notes
        case value        // 14 / 500  mono: timer, hotkey caps
        case valueSmall   // 12 / 500  mono: sizes, durations, language tags
    }

    enum Typography {
        static let textFamily = "Onest"
        static let monoFamily = "JetBrains Mono"

        /// True when the bundled face is registered. Resolved once: the fonts are
        /// registered at launch from `ATSApplicationFontsPath` and the set never
        /// changes afterwards, while the CoreText lookup costs milliseconds — far
        /// too much for a check on every `DS.font(_:)` call in a view body.
        static let isOnestAvailable: Bool = isFamilyAvailable(textFamily)
        static let isMonoAvailable: Bool = isFamilyAvailable(monoFamily)

        private static func isFamilyAvailable(_ family: String) -> Bool {
            ((CTFontManagerCopyAvailableFontFamilyNames() as? [String]) ?? []).contains(family)
        }
    }

    static func font(_ style: TextStyle) -> Font {
        switch style {
        case .display:    return text(24, .bold)
        case .section:    return text(22, .bold)
        case .title:      return text(17, .semibold)
        case .bodyLarge:  return text(15, .medium)
        case .body:       return text(13, .regular)
        case .bodyMedium: return text(13, .medium)
        case .caption:    return text(12, .regular)
        case .value:      return mono(14, .medium)
        case .valueSmall: return mono(12, .medium)
        }
    }

    /// Onest with a silent system fallback if the bundled font is missing.
    private static func text(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        Typography.isOnestAvailable
            ? Font.custom(Typography.textFamily, size: size).weight(weight)
            : Font.system(size: size, weight: weight)
    }

    /// JetBrains Mono with tabular digits; falls back to the system monospaced face.
    private static func mono(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        let base = Typography.isMonoAvailable
            ? Font.custom(Typography.monoFamily, size: size).weight(weight)
            : Font.system(size: size, weight: weight, design: .monospaced)
        return base.monospacedDigit()
    }
}
