import CoreGraphics

extension DS {
    /// Spacing scale, base unit 4 (spec §3.3).
    enum Space {
        static let s4: CGFloat = 4
        static let s8: CGFloat = 8
        static let s12: CGFloat = 12
        static let s16: CGFloat = 16
        static let s20: CGFloat = 20
        static let s28: CGFloat = 28
    }

    enum Radius {
        static let control: CGFloat = 6      // small controls, key caps
        static let row: CGFloat = 10
        static let card: CGFloat = 14
        static let overlayCard: CGFloat = 18
    }

    enum Size {
        static let settingsRow: CGFloat = 44
        static let popoverRow: CGFloat = 48
        /// Overlay capsule/card width. Never changes between states.
        static let overlayWidth: CGFloat = 420
        static let orb: CGFloat = 34
    }
}
