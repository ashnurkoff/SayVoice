import AppKit
import SwiftUI

/// The brand mark: six rounded bars in the app icon's asymmetric profile.
/// One geometry for every surface — the logo tile, the onboarding panel and
/// the menu-bar status icon — so the mark always reads as the same object.
struct WaveformMark: Shape {
    /// Bar heights as a fraction of the tallest bar, left to right.
    static let profile: [CGFloat] = [0.24, 0.62, 0.96, 0.52, 0.80, 0.30]
    /// Bar width and pitch as fractions of the mark's width (six bars).
    static let barWidth: CGFloat = 84.0 / 704.0
    static let pitch: CGFloat = 124.0 / 704.0
    /// Natural aspect ratio (width / height) of the mark.
    static let aspect: CGFloat = 704.0 / 640.0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (index, height) in Self.profile.enumerated() {
            let bar = Self.barRect(index: index, height: height, in: rect)
            path.addRoundedRect(in: bar, cornerSize: CGSize(width: bar.width / 2, height: bar.width / 2))
        }
        return path
    }

    /// The same bars as an AppKit path, for contexts that draw with `NSBezierPath`.
    static func bezierPath(in rect: CGRect) -> NSBezierPath {
        let path = NSBezierPath()
        for (index, height) in profile.enumerated() {
            let bar = barRect(index: index, height: height, in: rect)
            path.append(NSBezierPath(roundedRect: bar, xRadius: bar.width / 2, yRadius: bar.width / 2))
        }
        return path
    }

    private static func barRect(index: Int, height: CGFloat, in rect: CGRect) -> CGRect {
        let width = rect.width * barWidth
        let centreX = rect.minX + rect.width * (pitch * (CGFloat(index) - 2.5) + 0.5)
        let barHeight = rect.height * height
        return CGRect(x: centreX - width / 2, y: rect.midY - barHeight / 2, width: width, height: barHeight)
    }
}
