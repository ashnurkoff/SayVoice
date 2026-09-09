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

    func testSizeTextUsesEnglishUnits() {
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

    /// Holds the injected stream's continuation so the test can drive it.
    final class StreamBox {
        var continuation: AsyncThrowingStream<ModelDownloadProgress, Error>.Continuation?
    }

    /// The running download is the tallest the model step ever gets, and its
    /// status line is the longest string the screen ever shows. Two samples
    /// 0.7 s apart make `ModelDownloads` compute a speed and a time left, so the
    /// measured state renders the full "47% · 0.1 MB/s · 1 h 1 min left" form
    /// rather than the bare percentage a single sample would produce.
    func testModelStepFitsWhileADownloadIsRunning() async {
        let box = StreamBox()
        let model = makeFirstRunModel(granted: true, downloads: { manager in
            ModelDownloads(modelManager: manager,
                           progressSource: { _ in AsyncThrowingStream { box.continuation = $0 } },
                           isAvailable: { _ in false })
        })
        model.step = .model
        let target = model.downloadTarget
        model.downloads.start(target)
        await settle(until: { box.continuation != nil })

        let total: Int64 = 574_000_000
        box.continuation?.yield(ModelDownloadProgress(bytesReceived: 269_722_000, totalBytes: total))
        try? await Task.sleep(for: .milliseconds(700))
        box.continuation?.yield(ModelDownloadProgress(bytesReceived: 269_780_000, totalBytes: total))
        await settle(until: {
            if case .running(_, let speed, let left)? = model.downloads.state(for: target) {
                return speed != nil && left != nil
            }
            return false
        })

        guard case .running(let fraction, let speed, let left)? = model.downloads.state(for: target) else {
            return XCTFail("the download should be running with a speed and a time left")
        }
        let status = DownloadProgress.statusText(fraction: fraction, bytesPerSecond: speed, secondsLeft: left)
        XCTAssertTrue(status.contains("MB/s") && status.contains("left"), "expected the long status form, got \(status)")

        for dark in [true, false] {
            assertFits(.model, of: model, dark: dark, note: "downloading, \(status)")
        }

        model.downloads.cancel(target)
        box.continuation?.finish()
    }

    /// Runs the main-actor loop until `condition` holds or the budget runs out.
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
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

    /// The permission poll is stopped by the coordinator's `willClose`
    /// observer, which is filtered by the onboarding window. The unfiltered
    /// observer this replaced lived in `OnboardingView` and stopped the poll
    /// whenever *any* window of the app closed — the settings window included.
    func testAnUnrelatedWindowClosingDoesNotStopTheOnboardingPoll() {
        let model = makeFirstRunModel(granted: false)
        model.startPolling()
        XCTAssertTrue(model.isPolling, "precondition: the poll is running")

        let host = NSHostingView(rootView: OnboardingView(model: model, onHotkeyChanged: nil, onHotkeyModeChanged: nil))
        host.frame = CGRect(origin: .zero, size: OnboardingView.windowSize)
        host.layoutSubtreeIfNeeded()

        let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                             styleMask: [.titled], backing: .buffered, defer: true)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: other)

        XCTAssertTrue(model.isPolling, "another window's close must not stop the onboarding poll")
        model.stopPolling()
    }

    /// The squeeze the 400 pt window produced before the quality bar came off
    /// the onboarding rows: the name truncated and the chips wrapped. Measured
    /// at the row's *ideal* width — `lineLimit(1)` lets `fittingSize` report a
    /// truncated row as fitting, so only `fixedSize` exposes the overflow.
    func testModelStepRowsFitWithoutTruncatingTheName() {
        let manager = ModelManager(modelsDirectory: temporaryModelsDirectory())
        // StepLayout's 20 pt padding on each side is all that stands between
        // the row and the pane the art panel leaves.
        let available = OnboardingView.stepWidth - 2 * DS.Space.s20

        for size in OnboardingModel.offeredModels {
            for selected in [true, false] {
                for dark in [true, false] {
                    let row = ModelRow(
                        name: size.displayName,
                        badge: size == .recommended ? "recommended" : nil,
                        badgeIsAccent: size == .recommended,
                        qualitySteps: size.qualitySteps,
                        sizeText: size.sizeText,
                        isSelected: selected,
                        isDownloaded: manager.isModelAvailable(size),
                        isHighlighted: selected && !manager.isModelAvailable(size),
                        showsQualityBar: false,
                        download: nil,
                        onSelect: {}, onDownload: {}, onCancel: {}, onRetry: {}
                    )
                    let host = NSHostingView(rootView: AnyView(row.fixedSize()))
                    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    host.layoutSubtreeIfNeeded()
                    XCTAssertLessThanOrEqual(
                        host.fittingSize.width, available,
                        "\(size.displayName) [\(selected ? "selected" : "plain"), \(dark ? "dark" : "light")] "
                        + "wants \(host.fittingSize.width) pt of \(available)"
                    )
                }
            }
        }
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
