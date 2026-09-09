import AppKit
import XCTest
@testable import SayVoice

@MainActor
final class MenuBarTests: XCTestCase {
    func testStatusIconExistsForEveryStateAndOnlyIdleIsTemplate() {
        let states: [AppState] = [.idle, .recording, .transcribing, .injecting, .error(.modelNotLoaded)]
        for appearance in [NSAppearance(named: .darkAqua)!, NSAppearance(named: .aqua)!] {
            for s in states {
                let img = StatusIcon.image(for: s, appearance: appearance)
                XCTAssertGreaterThan(img.size.width, 10, "\(s)")
                XCTAssertEqual(img.isTemplate, s == .idle || isError(s), "\(s): template only for glyph-only icons")
            }
        }
    }
    private func isError(_ s: AppState) -> Bool { if case .error = s { return true } else { return false } }
}
