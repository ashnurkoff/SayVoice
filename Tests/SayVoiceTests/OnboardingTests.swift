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
        let m = OnboardingModel(permissions: p, settings: SettingsStore(defaults: TestDefaults.ephemeral()), modelManager: manager,
                                downloads: ModelDownloads(modelManager: manager), onFinished: onFinished)
        return (m, p)
    }

    func testStepsRunWelcomePermissionsModelHotkeyDone() {
        XCTAssertEqual(OnboardingStep.allCases, [.welcome, .permissions, .model, .hotkey, .done])
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

    func testModelAndHotkeyStepsCanBeSkippedAndTheDoneStepFinishes() {
        var finished = false
        let (m, _) = makeModel(mic: true, ax: true) { finished = true }
        m.next(); m.refreshPermissions(); m.next()   // → model
        XCTAssertTrue(m.canSkip)
        m.skip()                                      // → hotkey
        XCTAssertEqual(m.step, .hotkey)
        XCTAssertTrue(m.canSkip)
        m.next()                                      // → done
        XCTAssertEqual(m.step, .done)
        XCTAssertFalse(finished, "the hotkey step no longer ends onboarding")
        // The last step is a confirmation, not a decision: there is nothing to skip.
        XCTAssertFalse(m.canSkip)
        m.skip(); XCTAssertEqual(m.step, .done, "skip is a no-op on the last step")
        m.next()                                      // finish
        XCTAssertTrue(finished)
    }

    /// Item 2 of the owner's first round: a running transfer pins the step.
    /// Cancel is the way out; Continue is disabled and "Download later" is gone,
    /// both of which the view reads off these two properties.
    func testTheModelStepIsPinnedWhileTheTargetIsDownloading() async {
        let box = StreamBox()
        let model = makeFirstRunModel(granted: true, downloads: { manager in
            ModelDownloads(modelManager: manager,
                           progressSource: { _ in AsyncThrowingStream { box.continuation = $0 } },
                           isAvailable: { _ in false })
        })
        model.step = .model
        XCTAssertFalse(model.isDownloadingTarget)
        XCTAssertTrue(model.canSkip)
        XCTAssertTrue(model.canContinue)

        model.downloads.start(model.downloadTarget)
        await settle(until: { box.continuation != nil })

        XCTAssertTrue(model.isDownloadingTarget)
        XCTAssertEqual(model.runningDownload, .recommended, "the transfer is the recommended model's")
        XCTAssertFalse(model.canContinue, "Continue is disabled during a transfer")
        XCTAssertFalse(model.canSkip, "\"Download later\" is gone during a transfer")
        model.next(); model.skip()
        XCTAssertEqual(model.step, .model, "neither button may leave the step mid-download")

        // Nor may the rows: selecting another model would move the target out
        // from under the transfer that is already running.
        let selected = model.settings.modelSize
        model.select(.small)
        XCTAssertEqual(model.settings.modelSize, selected, "the selection is pinned too")
        XCTAssertEqual(model.downloadTarget, .recommended)
        XCTAssertFalse(model.canContinue, "still pinned after the attempt")
        if case .running? = model.downloads.state(for: .recommended) {} else {
            XCTFail("Cancel must still be on offer — the transfer is still running")
        }

        model.downloads.cancel(model.downloadTarget)
        XCTAssertFalse(model.isDownloadingTarget, "cancelling releases the step")
        XCTAssertTrue(model.canSkip)
        model.select(.small)
        XCTAssertEqual(model.settings.modelSize, ModelManager.ModelSize.small.settingsString,
                       "and the rows are choices again")
        box.continuation?.finish()
    }

    /// The callback closes the window and starts the app. A second Start —
    /// a double click, or a keyboard activation racing the mouse — must not
    /// start it twice.
    func testFinishingOnboardingFiresTheCallbackExactlyOnce() {
        var calls = 0
        let (m, _) = makeModel(mic: true, ax: true) { calls += 1 }
        m.step = .done
        m.next(); m.next(); m.skip()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(m.step, .done, "and the step machine stays where it is")
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
                XCTAssertLessThanOrEqual(fit.height, OnboardingView.windowSize.height + 0.5, "\(step) overflows \(OnboardingView.windowSize.height) pt (\(fit.height))")
                XCTAssertLessThanOrEqual(fit.width, OnboardingView.windowSize.width + 0.5, "\(step) overflows \(OnboardingView.windowSize.width) pt (\(fit.width))")
            }
        }
    }

    func testSizeTextUsesEnglishUnits() {
        // Compile-time guard: these members no longer exist.
        // (If this file compiles, the members are gone — the assertions below only keep the test non-empty.)
        XCTAssertEqual(ModelManager.ModelSize.turboQ5.sizeText, "574 MB")
    }

    // MARK: - Fitting size measured on the step pane itself

    /// The window's fixed 640 × 540 frame reports itself as the fitting size no
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

    func testModelStepOffersAllFiveModelsWithTurboQ5RecommendedFirst() {
        // Item 1 of the owner's first round: the subset is gone — first run
        // shows the same catalogue Settings does, in the same order.
        XCTAssertEqual(OnboardingModel.offeredModels, ModelManager.ModelSize.allCases)
        // Preselected on a fresh install: `SettingsStore` falls back to the
        // recommended model, and the row badged "recommended" is the same one.
        XCTAssertEqual(ModelManager.ModelSize.recommended, .turboQ5)
        XCTAssertTrue(OnboardingModel.offeredModels.contains(.recommended))
        // Whatever is stored, the footer always offers a download the step lists.
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

    /// The squeeze the narrow window produces without the quality bar off the
    /// onboarding rows: the name truncated and the chips wrapped. Measured
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
                    // Without the note: it is allowed to wrap, so its ideal
                    // width is wider than the pane by design. The name line is
                    // what must not be squeezed.
                    let row = ModelRow(
                        name: size.displayName,
                        badge: size == .recommended ? "Recommended" : nil,
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

    /// The last step names the hotkey the user actually has, not the default
    /// the copy was written against.
    func testDoneStepNamesTheCurrentHotkey() {
        let model = makeFirstRunModel(granted: true)
        model.step = .done
        let standard = DoneStep(model: model).message
        XCTAssertTrue(standard.contains(model.settings.hotkey.displayName), standard)

        // F13 — nothing like the Right ⌥ default.
        model.settings.hotkey = Hotkey(keyCode: 105, flags: 0, mouseButton: nil)
        let changed = DoneStep(model: model).message
        XCTAssertTrue(changed.contains(model.settings.hotkey.displayName), changed)
        XCTAssertNotEqual(changed, standard, "the sentence must follow the setting")
    }

    /// Item 12 of the owner's second round, measured on the rendered pane
    /// rather than asserted about the source: the mark sits above the title,
    /// both are centred in the pane, and Start is still hard against the
    /// bottom-right margin.
    func testDoneStepIsACentredColumnWithStartBottomRight() throws {
        let model = makeFirstRunModel(granted: true)
        model.step = .done
        let width = OnboardingView.stepWidth
        let height = OnboardingView.windowSize.height

        for dark in [true, false] {
            let appearance = try XCTUnwrap(NSAppearance(named: dark ? .darkAqua : .aqua))
            let host = NSHostingView(rootView: AnyView(
                DoneStep(model: model)
                    .frame(width: width, height: height)
                    .background(DS.Colors.ground.color)
            ))
            host.appearance = appearance
            host.frame = CGRect(origin: .zero, size: NSSize(width: width, height: height))
            host.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let ground = try XCTUnwrap(DS.Colors.ground.resolved(for: appearance).usingColorSpace(.sRGB))
            let scale = CGFloat(rep.pixelsWide) / width
            let theme = dark ? "dark" : "light"

            /// Left- and right-most point of anything drawn on one row.
            func ink(row y: Int) -> (left: CGFloat, right: CGFloat)? {
                var first: Int?
                var last: Int?
                for px in 0..<rep.pixelsWide {
                    guard let c = rep.colorAt(x: px, y: Int(CGFloat(y) * scale))?.usingColorSpace(.sRGB) else { continue }
                    let differs = abs(c.redComponent - ground.redComponent) > 0.02
                        || abs(c.greenComponent - ground.greenComponent) > 0.02
                        || abs(c.blueComponent - ground.blueComponent) > 0.02
                    if differs {
                        if first == nil { first = px }
                        last = px
                    }
                }
                guard let f = first, let l = last else { return nil }
                return (CGFloat(f) / scale, CGFloat(l) / scale)
            }

            /// Union of the ink on a band of rows, ignoring the empty ones.
            func box(rows: [Int]) -> (left: CGFloat, right: CGFloat)? {
                let spans = rows.compactMap(ink(row:))
                guard let first = spans.first else { return nil }
                return spans.dropFirst().reduce(first) { (min($0.left, $1.left), max($0.right, $1.right)) }
            }

            // Everything above the footer band, split into the runs of rows
            // that carry ink: the mark, then the title with its sentence.
            let column = Array(1..<Int(height) - 70)
            var runs: [[Int]] = []
            for y in column {
                if ink(row: y) != nil {
                    if var last = runs.last, let end = last.last, end == y - 1 {
                        last.append(y); runs[runs.count - 1] = last
                    } else {
                        runs.append([y])
                    }
                }
            }
            XCTAssertGreaterThanOrEqual(runs.count, 2, "[\(theme)] expected a mark and a title, found \(runs.count) blocks of ink")

            let mark = try XCTUnwrap(box(rows: runs[0]), "[\(theme)] no mark")
            let markHeight = CGFloat(runs[0].count)
            XCTAssertEqual(mark.right - mark.left, 72, accuracy: 24, "[\(theme)] the first block is not the 72 pt mark")
            XCTAssertEqual(markHeight, 72, accuracy: 24, "[\(theme)] the first block is not the 72 pt mark")
            XCTAssertEqual((mark.left + mark.right) / 2, width / 2, accuracy: 6,
                           "[\(theme)] the mark is not centred (\(mark.left)…\(mark.right) of \(width))")

            // The title is the top of the second block — the mark is above it.
            let title = try XCTUnwrap(box(rows: Array(runs[1].prefix(20))), "[\(theme)] no title under the mark")
            XCTAssertLessThan(runs[0].last ?? 0, runs[1].first ?? 0, "[\(theme)] the mark is not above the title")
            XCTAssertEqual((title.left + title.right) / 2, width / 2, accuracy: 12,
                           "[\(theme)] the title is not centred (\(title.left)…\(title.right) of \(width))")
            XCTAssertGreaterThan(title.left, 40, "[\(theme)] the title still starts at the leading margin")

            // …and Start is where it always was: bottom-right.
            let footer = try XCTUnwrap(box(rows: Array(Int(height) - 60..<Int(height) - 12)), "[\(theme)] no footer button")
            XCTAssertGreaterThan(footer.left, width / 2, "[\(theme)] Start is not on the right")
            XCTAssertEqual(footer.right, width - DS.Space.s20, accuracy: 4,
                           "[\(theme)] Start is \(width - footer.right) pt from the trailing margin")
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
                                 "\(step) [\(note), \(theme)] overflows \(OnboardingView.windowSize.height) pt (\(size.height))", file: file, line: line)
        XCTAssertLessThanOrEqual(size.width, OnboardingView.stepWidth + 0.5,
                                 "\(step) [\(note), \(theme)] overflows \(OnboardingView.stepWidth) pt (\(size.width))", file: file, line: line)
    }

    private func makeFirstRunModel(
        granted: Bool,
        downloads: (ModelManager) -> ModelDownloads = { ModelDownloads(modelManager: $0) }
    ) -> OnboardingModel {
        let manager = ModelManager(modelsDirectory: temporaryModelsDirectory())
        let permissions = FakePermissions(); permissions.mic = granted; permissions.ax = granted
        return OnboardingModel(permissions: permissions, settings: SettingsStore(defaults: TestDefaults.ephemeral()), modelManager: manager,
                               downloads: downloads(manager), onFinished: {})
    }

    private func temporaryModelsDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SayVoiceTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
