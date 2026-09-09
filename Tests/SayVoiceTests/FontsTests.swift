import CoreText
import XCTest
@testable import SayVoice

/// The bundled fonts must be registered by the time any view is built.
/// Registration is done by AppKit from `ATSApplicationFontsPath`; if the
/// folder reference or the plist key is wrong, these families are missing.
final class FontsTests: XCTestCase {

    private var families: [String] {
        (CTFontManagerCopyAvailableFontFamilyNames() as? [String]) ?? []
    }

    func testOnestIsRegistered() {
        XCTAssertTrue(families.contains("Onest"), "Onest not registered; families: \(families.filter { $0.hasPrefix("O") })")
    }

    func testJetBrainsMonoIsRegistered() {
        XCTAssertTrue(families.contains("JetBrains Mono"), "JetBrains Mono not registered")
    }
}
