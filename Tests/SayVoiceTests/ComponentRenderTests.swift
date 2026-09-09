import SwiftUI
import XCTest
@testable import SayVoice

/// Smoke tests: each component renders to a bitmap with a sane size in
/// both appearances. They catch layout that collapses to zero and code
/// paths that crash off-screen; they do not judge looks.
@MainActor
final class ComponentRenderTests: XCTestCase {

    func renderSize<V: View>(_ view: V, width: CGFloat? = nil, dark: Bool = true) -> CGSize {
        let host = NSHostingView(rootView: AnyView(view.fixedSize(horizontal: width == nil, vertical: true).frame(width: width)))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let size = host.fittingSize
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)
        XCTAssertNotNil(rep)
        if let rep { host.cacheDisplay(in: host.bounds, to: rep) }
        return size
    }

    func testChipRendersAllStyles() {
        for style in [Chip.Style.neutral, .accent, .ok, .warn] {
            for dark in [true, false] {
                let s = renderSize(Chip("recommended", style: style), dark: dark)
                XCTAssertGreaterThan(s.width, 40); XCTAssertGreaterThan(s.height, 16); XCTAssertLessThan(s.height, 30)
            }
        }
    }

    func testKeyCapRenders() {
        let s = renderSize(KeyCap("⌃⌥⌘D"))
        XCTAssertGreaterThan(s.width, 40); XCTAssertGreaterThan(s.height, 20)
    }

    func testButtonStylesRender() {
        XCTAssertGreaterThan(renderSize(Button("Download") {}.buttonStyle(.dsPrimary)).height, 24)
        XCTAssertGreaterThan(renderSize(Button("Stop") {}.buttonStyle(.dsSecondary)).height, 24)
        XCTAssertGreaterThan(renderSize(Button("Copy") {}.buttonStyle(.dsLink)).height, 14)
        XCTAssertGreaterThan(renderSize(Button("Clear…") {}.buttonStyle(.dsDestructive)).height, 14)
    }

    func testOrbRendersEveryState() {
        for state in [Orb.State.idle, .recording, .transcribing, .done, .error] {
            let s = renderSize(Orb(state: state))
            XCTAssertEqual(s.width, DS.Size.orb + 10, accuracy: 0.5, "orb frame includes the 5pt halo ring")
            XCTAssertEqual(s.height, DS.Size.orb + 10, accuracy: 0.5)
        }
    }
}
