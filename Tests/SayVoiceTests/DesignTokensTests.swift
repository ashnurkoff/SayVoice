import AppKit
import XCTest
@testable import SayVoice

final class DesignTokensTests: XCTestCase {

    private func hex(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB)!
        return String(format: "#%02X%02X%02X", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }

    func testGroundResolvesPerAppearance() {
        XCTAssertEqual(hex(DS.Colors.ground.resolved(for: NSAppearance(named: .darkAqua)!)), "#17171D")
        XCTAssertEqual(hex(DS.Colors.ground.resolved(for: NSAppearance(named: .aqua)!)), "#F7F7FB")
    }

    func testAccentResolvesPerAppearance() {
        XCTAssertEqual(hex(DS.Colors.accent.resolved(for: NSAppearance(named: .darkAqua)!)), "#7B7FF2")
        XCTAssertEqual(hex(DS.Colors.accent.resolved(for: NSAppearance(named: .aqua)!)), "#5B5FD6")
    }

    func testLineIsTranslucent() {
        let dark = DS.Colors.line.resolved(for: NSAppearance(named: .darkAqua)!).usingColorSpace(.sRGB)!
        XCTAssertEqual(dark.alphaComponent, 0.07, accuracy: 0.005)
        XCTAssertEqual(dark.redComponent, 1.0, accuracy: 0.001)
    }

    func testFontsUseBundledFacesWhenAvailable() {
        XCTAssertTrue(DS.Typography.isOnestAvailable)
        XCTAssertTrue(DS.Typography.isMonoAvailable)
    }

    func testSpacingScale() {
        XCTAssertEqual([DS.Space.s8, DS.Space.s12, DS.Space.s16, DS.Space.s20, DS.Space.s28], [8, 12, 16, 20, 28])
        XCTAssertEqual(DS.Size.overlayWidth, 420)
    }
}
