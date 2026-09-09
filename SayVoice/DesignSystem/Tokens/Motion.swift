import SwiftUI

extension EnvironmentValues {
    /// Renders motion in its resting state, as Reduce Motion does. Set by the
    /// screenshot harness, which captures one frame and would otherwise catch a
    /// one-shot entrance halfway through it; `accessibilityReduceMotion` itself
    /// is read-only, so this is the switch a renderer can throw. Same idea as
    /// `dsGlassFallback` for the overlay.
    @Entry var dsStaticMotion: Bool = false
}

extension DS {
    /// Motion tokens (spec §3.4). Views must also honour
    /// `accessibilityReduceMotion`; these are the values for when motion is on.
    enum Motion {
        static let stateChange: Animation = .easeOut(duration: 0.18)
        static let orb: Animation = .spring(response: 0.35, dampingFraction: 0.7)
        static let pulseDuration: Double = 1.2
        static let breathDuration: Double = 1.6
        static let resultAutoDismiss: Double = 2.0
        /// Error card without an action: long enough to read, short enough
        /// not to sit on top of another app.
        static let errorAutoDismiss: Double = 3.0
        /// Error card carrying a button: the user needs time to reach for it,
        /// but the card must still go away on its own.
        static let errorWithActionAutoDismiss: Double = 8.0
        /// Upper bound on the hover pause before an auto-dismiss: a pointer
        /// resting on the panel must not keep it up forever.
        static let hoverPauseLimit: Double = 10
    }
}
