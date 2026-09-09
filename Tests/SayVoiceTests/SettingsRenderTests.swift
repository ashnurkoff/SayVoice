import SwiftUI
import XCTest
@testable import SayVoice

@MainActor
final class SettingsRenderTests: XCTestCase {

    func makeView(section: SettingsSection) -> SettingsView {
        let settings = SettingsStore(defaults: TestDefaults.ephemeral())
        let status = AppStatus(); status.modelName = "Large Turbo Q5"
        let router = SettingsRouter(); router.section = section
        // A temp models directory keeps the rendered rows the same on any Mac,
        // whether or not models are installed.
        let manager = ModelManager(modelsDirectory: temporaryModelsDirectory())
        return SettingsView(settings: settings, status: status, router: router,
                            downloads: ModelDownloads(modelManager: manager), modelManager: manager,
                            onHotkeyChanged: nil, onHotkeyModeChanged: nil)
    }

    private func temporaryModelsDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SayVoiceTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// Fitting height of one section's content column at the window's content width.
    func contentHeight(_ section: SettingsSection, dark: Bool) -> CGFloat {
        let host = NSHostingView(rootView: makeView(section: section))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = CGRect(origin: .zero, size: SettingsView.windowSize)
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        return SettingsView.measuredContentHeight(for: section, hosting: host)
    }

    func testGeneralFitsWithoutScrolling() {
        for dark in [true, false] {
            XCTAssertLessThanOrEqual(contentHeight(.general, dark: dark), SettingsView.windowSize.height, "General must fit in 600 pt")
        }
    }

    func testRecognitionRendersAndMayScroll() {
        for dark in [true, false] {
            let h = contentHeight(.recognition, dark: dark)
            XCTAssertGreaterThan(h, 200)
            XCTAssertLessThan(h, 1200, "unexpectedly tall — check for a runaway layout")
        }
    }

    func testDictionaryInsertionSystemFitWithoutScrolling() {
        for section in [SettingsSection.dictionary, .insertion, .system] {
            for dark in [true, false] {
                XCTAssertLessThanOrEqual(contentHeight(section, dark: dark), SettingsView.windowSize.height, "\(section) must fit in 600 pt")
            }
        }
    }

    /// Item 8 of the owner's first round: Language is one row and the setting
    /// changed most often, so it sits above the five model rows and is visible
    /// without scrolling; and Recognition is the one section whose content runs
    /// to the window's bottom edge instead of stopping short of it.
    func testRecognitionPutsLanguageFirstAndReachesTheBottomEdge() {
        XCTAssertEqual(RecognitionSection.cardOrder, [.language, .model])
        XCTAssertTrue(SettingsSection.recognition.scrollsToBottomEdge)
        for section in SettingsSection.allCases where section != .recognition {
            XCTAssertFalse(section.scrollsToBottomEdge, "\(section) does not scroll")
        }
    }

    /// The rail chrome must cover all 64 pt. Its buttons are only 40 pt wide,
    /// so without the width frame the fill — and the hairline it carries —
    /// would float in the middle and the backdrop would show at both edges.
    func testRailFillSpansTheFullWidth() throws {
        for dark in [true, false] {
            let host = NSHostingView(rootView: AnyView(
                ZStack(alignment: .leading) {
                    Color.red   // shows through anywhere the rail fails to paint
                    SettingsRail(selected: .general, onSelect: { _ in }).frame(width: SettingsView.railWidth)
                }
                .frame(width: SettingsView.railWidth, height: 600)))
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            host.frame = CGRect(origin: .zero, size: NSSize(width: SettingsView.railWidth, height: 600))
            host.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)

            // A scanline well below the last icon, so it crosses nothing but
            // the rail's own background.
            let scale = CGFloat(rep.pixelsWide) / SettingsView.railWidth
            let y = Int(300 * scale)
            let centre = try XCTUnwrap(rep.colorAt(x: rep.pixelsWide / 2, y: y)?.usingColorSpace(.sRGB))
            for x in 0..<rep.pixelsWide {
                let pixel = try XCTUnwrap(rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                // The backdrop is pure red; the rail's translucent fill over it
                // is never that saturated.
                XCTAssertFalse(pixel.redComponent > 0.9 && pixel.greenComponent < 0.1,
                               "the backdrop shows through the rail at x=\(x) of \(rep.pixelsWide), dark=\(dark)")
            }
            // The fill reaches the leading edge unchanged.
            let leading = try XCTUnwrap(rep.colorAt(x: 0, y: y)?.usingColorSpace(.sRGB))
            XCTAssertEqual(leading.greenComponent, centre.greenComponent, accuracy: 0.02, "dark=\(dark)")
        }
    }

    func testLicenseTextsAreBundled() {
        for item in LicensesSheet.items {
            XCTAssertFalse(item.text.isEmpty, "\(item.name) licence text missing from the bundle")
            XCTAssertTrue(item.text.contains("Permission is hereby granted") || item.text.contains("SIL OPEN FONT LICENSE"), item.name)
        }
    }
}
