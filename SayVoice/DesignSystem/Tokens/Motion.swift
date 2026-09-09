import SwiftUI

extension DS {
    /// Motion tokens (spec §3.4). Views must also honour
    /// `accessibilityReduceMotion`; these are the values for when motion is on.
    enum Motion {
        static let stateChange: Animation = .easeOut(duration: 0.18)
        static let orb: Animation = .spring(response: 0.35, dampingFraction: 0.7)
        static let pulseDuration: Double = 1.2
        static let breathDuration: Double = 1.6
        static let resultAutoDismiss: Double = 2.0
    }
}
