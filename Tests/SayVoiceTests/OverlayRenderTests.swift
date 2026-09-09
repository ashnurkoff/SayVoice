import SwiftUI
import XCTest
@testable import SayVoice

@MainActor
final class OverlayRenderTests: XCTestCase {

    private func render(_ model: OverlayModel) -> CGSize {
        let host = NSHostingView(rootView: OverlayView(model: model))
        host.frame = CGRect(origin: .zero, size: OverlayWindowController.panelSize)
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        return host.fittingSize
    }

    func testHiddenStateKeepsNonZeroBacking() {
        let m = OverlayModel()
        m.displayState = .hidden
        let s = render(m)
        XCTAssertGreaterThan(s.width, 0,
                             "the Color.clear backing must keep the hosting view from collapsing")
    }

    func testEveryStateRenders() {
        for state in [OverlayModel.DisplayState.recording, .transcribing, .result, .error] {
            let m = OverlayModel()
            m.displayState = state
            m.message = "Let's discuss the sync module architecture; the client polls the server every thirty seconds."
            m.isToggleMode = true
            m.hotkeyName = "⌃⌥⌘D"
            m.durationSeconds = 12.4
            m.errorAction = ("Open System Settings", {})
            _ = render(m)
        }
    }
}
