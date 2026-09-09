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

    /// Item 8 of the owner's first round, measured on the rendered window
    /// rather than asserted about the source: the first card under the header
    /// is the short one (Language, not the five model rows), it ends well above
    /// the fold, and its trailing edge lines up with the header pill's — the
    /// scroll area gave up only its bottom margin, not its right one.
    func testRecognitionLeadsWithLanguageAndKeepsTheHeaderMargins() throws {
        XCTAssertEqual(RecognitionSection.cardOrder, [.language, .model])
        XCTAssertTrue(SettingsSection.recognition.scrollsToBottomEdge)
        for section in SettingsSection.allCases where section != .recognition {
            XCTAssertFalse(section.scrollsToBottomEdge, "\(section) does not scroll")
        }

        for dark in [true, false] {
            let probe = try WindowProbe(view: makeView(section: .recognition), dark: dark)

            // Trailing edges: the pill's band, then the first card's band.
            let pillEdge = probe.rightMostSurface(rows: 40...90)
            // A column of bare card fill: past the card's own border, short of
            // the 16 pt its content is inset by.
            let fill: CGFloat = 100
            let cardTop = try XCTUnwrap(probe.firstSurfaceRow(inColumn: fill, below: 90), "no card under the header")
            let cardBottom = try XCTUnwrap(probe.firstGroundRow(inColumn: fill, below: cardTop + 4), "the first card never ends")
            let cardEdge = probe.rightMostSurface(rows: Int(cardTop + 8)...Int(cardBottom - 8))
            // 2 pt, not 1: the pill is a capsule, and the antialiased pixel at
            // the tangent of its curve fails a strict fill match, so its edge
            // measures about a point inside a card's straight one. The
            // card-against-card check below is the exact one.
            XCTAssertEqual(cardEdge, pillEdge, accuracy: 2,
                           "the card's trailing edge (\(cardEdge)) must match the header pill's (\(pillEdge)), dark=\(dark)")

            // …and General, which never lost its margin, agrees with both.
            let general = try WindowProbe(view: makeView(section: .general), dark: dark)
            XCTAssertEqual(cardEdge, general.rightMostSurface(rows: 140...200), accuracy: 1,
                           "Recognition's cards must line up with every other section's, dark=\(dark)")

            // The first card is the one-row Language card, not the model list…
            XCTAssertLessThan(cardBottom - cardTop, 200,
                              "the first card is \(cardBottom - cardTop) pt tall — that is the model list, not Language")
            // …and it is fully visible under the header, without scrolling.
            XCTAssertLessThan(cardBottom, SettingsView.windowSize.height - cardTop,
                              "Language ends at \(cardBottom), below the fold, dark=\(dark)")
        }
    }

    /// A rendered settings window, with the few pixel questions the layout
    /// tests ask of it. Points, not pixels: every value is divided back down by
    /// the backing scale.
    private struct WindowProbe {
        let rep: NSBitmapImageRep
        let surface: NSColor
        let scale: CGFloat

        @MainActor
        init(view: SettingsView, dark: Bool) throws {
            let appearance = try XCTUnwrap(NSAppearance(named: dark ? .darkAqua : .aqua))
            let host = NSHostingView(rootView: view)
            host.appearance = appearance
            host.frame = CGRect(origin: .zero, size: SettingsView.windowSize)
            host.layoutSubtreeIfNeeded()
            rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            surface = try XCTUnwrap(DS.Colors.surface.resolved(for: appearance).usingColorSpace(.sRGB))
            scale = CGFloat(rep.pixelsWide) / SettingsView.windowSize.width
        }

        /// The fill a card and the status pill share. Matched rather than
        /// "anything that is not the ground" because on light the card's drop
        /// shadow tints the ground for two points past the border, and that
        /// shadow is not the edge anyone is aligning to.
        func isSurface(x: CGFloat, y: CGFloat) -> Bool {
            guard let c = rep.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB) else { return false }
            return abs(c.redComponent - surface.redComponent) < 0.012
                && abs(c.greenComponent - surface.greenComponent) < 0.012
                && abs(c.blueComponent - surface.blueComponent) < 0.012
        }

        /// Right-most column of card fill over a band of rows — the trailing
        /// edge of whatever the band crosses, one point inside its border.
        func rightMostSurface(rows: ClosedRange<Int>) -> CGFloat {
            var best: CGFloat = 0
            for y in rows {
                for px in stride(from: rep.pixelsWide - 1, through: 0, by: -1) {
                    let x = CGFloat(px) / scale
                    if isSurface(x: x, y: CGFloat(y)) { best = max(best, x); break }
                }
            }
            return best
        }

        func firstSurfaceRow(inColumn x: CGFloat, below y: CGFloat) -> CGFloat? {
            (Int(y)..<Int(SettingsView.windowSize.height)).first { isSurface(x: x, y: CGFloat($0)) }.map(CGFloat.init)
        }

        func firstGroundRow(inColumn x: CGFloat, below y: CGFloat) -> CGFloat? {
            (Int(y)..<Int(SettingsView.windowSize.height)).first { !isSurface(x: x, y: CGFloat($0)) }.map(CGFloat.init)
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
