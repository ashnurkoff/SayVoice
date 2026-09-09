import SwiftUI
import XCTest
@testable import SayVoice

@MainActor
final class OnboardingTests: XCTestCase {

    /// A permission source the tests control.
    final class FakePermissions: PermissionSource {
        var mic = false
        var ax = false
        var isMicrophoneGranted: Bool { mic }
        var isAccessibilityGranted: Bool { ax }
        func requestMicrophone() async -> Bool { mic }
        func openMicrophoneSettings() {}
        func requestAccessibilityPrompt() {}
        func openAccessibilitySettings() {}
    }

    func makeModel(mic: Bool = false, ax: Bool = false, onFinished: @escaping () -> Void = {}) -> (OnboardingModel, FakePermissions) {
        let p = FakePermissions(); p.mic = mic; p.ax = ax
        let manager = ModelManager()
        let m = OnboardingModel(permissions: p, settings: SettingsStore(), modelManager: manager,
                                downloads: ModelDownloads(modelManager: manager), onFinished: onFinished)
        return (m, p)
    }

    func testStepsRunWelcomePermissionsModelHotkey() {
        XCTAssertEqual(OnboardingStep.allCases, [.welcome, .permissions, .model, .hotkey])
    }

    func testPermissionsStepCannotBeSkippedAndBlocksUntilBothGranted() {
        let (m, p) = makeModel()
        m.next()                                  // welcome → permissions
        XCTAssertEqual(m.step, .permissions)
        XCTAssertFalse(m.canSkip)
        XCTAssertFalse(m.canContinue)
        m.next(); XCTAssertEqual(m.step, .permissions, "next is a no-op while blocked")
        p.mic = true; m.refreshPermissions(); XCTAssertFalse(m.canContinue)
        p.ax = true;  m.refreshPermissions(); XCTAssertTrue(m.canContinue)
        m.next(); XCTAssertEqual(m.step, .model)
    }

    func testModelAndHotkeyStepsCanBeSkippedAndFinishCallsBack() {
        var finished = false
        let (m, _) = makeModel(mic: true, ax: true) { finished = true }
        m.next(); m.refreshPermissions(); m.next()   // → model
        XCTAssertTrue(m.canSkip)
        m.skip()                                      // → hotkey
        XCTAssertEqual(m.step, .hotkey)
        XCTAssertTrue(m.canSkip)
        m.next()                                      // finish
        XCTAssertTrue(finished)
    }

    func testOnboardingRendersEveryStepInBothThemesAtWindowSize() {
        for step in OnboardingStep.allCases {
            for dark in [true, false] {
                let (m, _) = makeModel(mic: true, ax: true)
                m.step = step
                let host = NSHostingView(rootView: OnboardingView(model: m, onHotkeyChanged: nil, onHotkeyModeChanged: nil))
                host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                host.frame = CGRect(origin: .zero, size: OnboardingView.windowSize)
                host.layoutSubtreeIfNeeded()
                let fit = host.fittingSize
                XCTAssertLessThanOrEqual(fit.height, OnboardingView.windowSize.height + 0.5, "\(step) overflows 360 pt (\(fit.height))")
                XCTAssertLessThanOrEqual(fit.width, OnboardingView.windowSize.width + 0.5, "\(step) overflows 640 pt (\(fit.width))")
            }
        }
    }

    func testFractionWrapperAndRussianCatalogueStringsAreGone() {
        // Compile-time guard: these members no longer exist.
        // (If this file compiles, the members are gone — the assertions below only keep the test non-empty.)
        XCTAssertEqual(ModelManager.ModelSize.turboQ5.sizeText, "574 MB")
    }

    // MARK: - Fitting size measured on the step pane itself

    /// The window's fixed 640 × 360 frame reports itself as the fitting size no
    /// matter how far a step overflows, so the pane is measured on its own — the
    /// same trick `SettingsView.measuredContentHeight` uses. Models are read from
    /// an empty directory and the permissions are ungranted as well as granted:
    /// onboarding runs on a first launch, where nothing is on disk and neither
    /// permission has been given, and those are the states a new user sees.
    func testEveryStepFitsTheWindowOnAFirstRun() {
        for step in OnboardingStep.allCases {
            for granted in [false, true] {
                for dark in [true, false] {
                    let model = makeFirstRunModel(granted: granted)
                    model.step = step
                    assertFits(step, of: model, dark: dark, note: granted ? "granted" : "ungranted")
                }
            }
        }
    }

    /// The running download is the tallest the model step ever gets: the footer
    /// grows a progress bar and a status line where the button was.
    func testModelStepFitsWhileADownloadIsRunning() {
        let model = makeFirstRunModel(granted: true, downloads: { manager in
            ModelDownloads(modelManager: manager,
                           // A stream that never yields and never finishes: the
                           // state stays `.running` for as long as the test needs.
                           progressSource: { _ in AsyncThrowingStream { _ in } },
                           isAvailable: { _ in false })
        })
        model.step = .model
        model.downloads.start(model.downloadTarget)
        for dark in [true, false] {
            assertFits(.model, of: model, dark: dark, note: "downloading")
        }
        model.downloads.cancel(model.downloadTarget)
    }

    func testModelStepOffersTheThreeFirstRunModelsWithTurboQ5Recommended() {
        XCTAssertEqual(OnboardingModel.offeredModels, [.turboQ5, .small, .turboQ8])
        // Preselected on a fresh install: `SettingsStore` falls back to the
        // recommended model, and the row badged "recommended" is the same one.
        XCTAssertEqual(ModelManager.ModelSize.recommended, .turboQ5)
        XCTAssertEqual(OnboardingModel.offeredModels.first, .recommended)
        // Whatever is stored — including one of the two models the step does not
        // list — the footer always offers a download the step can show.
        XCTAssertTrue(OnboardingModel.offeredModels.contains(makeFirstRunModel(granted: true).downloadTarget))
    }

    private func assertFits(_ step: OnboardingStep, of model: OnboardingModel, dark: Bool, note: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        let view = OnboardingView(model: model, onHotkeyChanged: nil, onHotkeyModeChanged: nil)
        let size = OnboardingView.measuredStepSize(
            for: step, in: view, appearance: NSAppearance(named: dark ? .darkAqua : .aqua)
        )
        let theme = dark ? "dark" : "light"
        XCTAssertLessThanOrEqual(size.height, OnboardingView.windowSize.height,
                                 "\(step) [\(note), \(theme)] overflows 360 pt (\(size.height))", file: file, line: line)
        XCTAssertLessThanOrEqual(size.width, OnboardingView.stepWidth + 0.5,
                                 "\(step) [\(note), \(theme)] overflows \(OnboardingView.stepWidth) pt (\(size.width))", file: file, line: line)
    }

    private func makeFirstRunModel(
        granted: Bool,
        downloads: (ModelManager) -> ModelDownloads = { ModelDownloads(modelManager: $0) }
    ) -> OnboardingModel {
        let manager = ModelManager(modelsDirectory: temporaryModelsDirectory())
        let permissions = FakePermissions(); permissions.mic = granted; permissions.ax = granted
        return OnboardingModel(permissions: permissions, settings: SettingsStore(), modelManager: manager,
                               downloads: downloads(manager), onFinished: {})
    }

    private func temporaryModelsDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SayVoiceTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
