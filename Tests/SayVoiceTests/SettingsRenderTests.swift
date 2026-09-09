import SwiftUI
import XCTest
@testable import SayVoice

@MainActor
final class SettingsRenderTests: XCTestCase {

    func makeView(section: SettingsSection) -> SettingsView {
        let settings = SettingsStore()
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

    func testLicenseTextsAreBundled() {
        for item in LicensesSheet.items {
            XCTAssertFalse(item.text.isEmpty, "\(item.name) licence text missing from the bundle")
            XCTAssertTrue(item.text.contains("Permission is hereby granted") || item.text.contains("SIL OPEN FONT LICENSE"), item.name)
        }
    }
}
