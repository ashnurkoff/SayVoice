import SwiftUI
import XCTest
@testable import SayVoice

/// Renders every surface in both appearances into `$SAYVOICE_RENDER_DIR` as
/// `<surface>-<theme>.png`, so the README screenshots are generated from the
/// code rather than captured by hand. The whole class is skipped unless the
/// variable is set — a plain `xcodebuild test` writes nothing. Run it through
/// `Scripts/render-surfaces`.
///
/// Known limits of the off-screen renderer, all of them expected:
/// - Liquid Glass has no live backdrop off screen, and `glassEffect` then
///   captures as an opaque slab covering its own content, so the overlay is
///   rendered with `dsGlassFallback` — the flat `glassFill` tint the spec
///   defines for exactly this case — over a plain `ground` stand-in for the
///   desktop the panel really floats above.
/// - Prominent and focused controls render inactive: the hosting view belongs
///   to no key window.
/// - The waveform renders flat. `BarEngine` smooths towards the level over
///   successive frames, and a capture is always the first one.
/// - Hover-only affordances — the Copy action on a history row — are absent.
@MainActor
final class SurfaceScreenshotTests: XCTestCase {

    // MARK: - Surfaces

    func testRendersOverlayStates() throws {
        let directory = try outputDirectory()
        var failures: [String] = []

        for state in [OverlayModel.DisplayState.recording, .transcribing, .result, .error] {
            failures += renderSurface(overlayScene(state), size: OverlayWindowController.panelSize,
                                      name: "overlay-\(state)", into: directory)
        }
        report(failures)
    }

    func testRendersSettingsSections() throws {
        let directory = try outputDirectory()
        var failures: [String] = []

        for section in SettingsSection.allCases {
            failures += renderSurface(settings(section: section), size: SettingsView.windowSize,
                                      name: "settings-\(section.rawValue)", into: directory)
        }
        report(failures)
    }

    func testRendersOnboardingSteps() throws {
        let directory = try outputDirectory()
        var failures: [String] = []

        for step in OnboardingStep.allCases {
            failures += renderSurface(onboarding(step: step), size: OnboardingView.windowSize,
                                      name: "onboarding-\(step)", into: directory)
        }
        report(failures)
    }

    func testRendersHistoryPopover() throws {
        let directory = try outputDirectory()
        var failures: [String] = []

        failures += renderSurface(popover(entries: []), size: nil, name: "history-empty", into: directory)
        failures += renderSurface(popover(entries: Self.sampleEntries()), size: nil,
                                  name: "history-filled", into: directory)
        report(failures)
    }

    // MARK: - Per-surface reporting

    /// Renders one surface inside an activity of its own, so the report names
    /// the surface that broke, and returns the failure instead of throwing, so
    /// the run goes on to the next surface: one bad layout must not hide the
    /// state of every surface after it.
    private func renderSurface<V: View>(_ view: @autoclosure () -> V, size: CGSize?,
                                        name: String, into directory: URL) -> [String] {
        XCTContext.runActivity(named: name) { _ in
            do {
                try render(view(), size: size, name: name, into: directory)
                return []
            } catch {
                return ["\(name): \(error)"]
            }
        }
    }

    /// One failure for the whole set, listing every surface that did not render.
    private func report(_ failures: [String], file: StaticString = #filePath, line: UInt = #line) {
        guard !failures.isEmpty else { return }
        XCTFail("\(failures.count) surface(s) failed to render:\n" + failures.joined(separator: "\n"),
                file: file, line: line)
    }

    // MARK: - Surface builders

    private func overlayScene(_ state: OverlayModel.DisplayState) -> some View {
        ZStack {
            DS.Colors.ground.color
            overlay(state)
        }
        .environment(\.dsGlassFallback, true)
    }

    private func overlay(_ state: OverlayModel.DisplayState) -> OverlayView {
        let model = OverlayModel()
        model.displayState = state
        model.hotkeyName = "Right ⌥"
        // A fresh start date renders 0:00 on every run, which keeps the PNG
        // byte-identical; a fixed date would show an ever-growing elapsed time.
        model.recordingStart = Date()
        model.durationSeconds = 12.4
        switch state {
        case .result:
            model.message = "Let's discuss the sync module architecture; the client polls the server every thirty seconds."
            model.onCopy = {}
            model.onShowAll = {}
        case .error:
            model.message = "Enable SayVoice in Accessibility"
            model.errorAction = ("Open System Settings", {})
        default:
            break
        }
        return OverlayView(model: model)
    }

    private func settings(section: SettingsSection) -> SettingsView {
        let status = AppStatus()
        status.modelName = ModelManager.ModelSize.recommended.displayName
        let router = SettingsRouter()
        router.section = section
        let manager = ModelManager(modelsDirectory: temporaryModelsDirectory())
        return SettingsView(settings: SettingsStore(defaults: TestDefaults.ephemeral()), status: status, router: router,
                            downloads: ModelDownloads(modelManager: manager), modelManager: manager,
                            onHotkeyChanged: nil, onHotkeyModeChanged: nil)
    }

    private func onboarding(step: OnboardingStep) -> OnboardingView {
        let permissions = OnboardingTests.FakePermissions()
        // Granted on the permissions step too: the screenshots show the state a
        // user reaches, not the one that blocks them.
        permissions.mic = true
        permissions.ax = true
        let manager = ModelManager(modelsDirectory: temporaryModelsDirectory())
        let model = OnboardingModel(permissions: permissions, settings: SettingsStore(defaults: TestDefaults.ephemeral()),
                                    modelManager: manager, downloads: ModelDownloads(modelManager: manager),
                                    onFinished: {})
        model.step = step
        return OnboardingView(model: model, onHotkeyChanged: nil, onHotkeyModeChanged: nil)
    }

    private func popover(entries: [TranscriptionEntry]) -> HistoryPopover {
        let status = AppStatus()
        status.modelName = ModelManager.ModelSize.recommended.displayName
        return HistoryPopover(entries: entries, status: status, hotkeyName: "Right ⌥",
                              onClear: {}, onSettings: {})
    }

    /// Entries are stamped with the current date, so the relative time reads
    /// "just now" on every run and the PNG stays byte-identical.
    private static func sampleEntries() -> [TranscriptionEntry] {
        [
            TranscriptionEntry(text: "Let's discuss the sync module architecture; the client polls the server every thirty seconds.",
                               durationSeconds: 12.4, language: "en"),
            TranscriptionEntry(text: "Remember to rotate the API keys before the release.", durationSeconds: 4.1, language: "en"),
            TranscriptionEntry(text: "Draft a reply to the design review and send it tomorrow morning.", durationSeconds: 6.8, language: "en"),
        ]
    }

    // MARK: - Renderer

    /// `nil` size means the view's own fitting size. The popover is the only
    /// surface that sizes itself, and its list reports its height back through
    /// the view state one layout pass late, so that size is read until it
    /// settles — otherwise the capture shows the list stretched to its cap.
    private func render<V: View>(_ view: V, size: CGSize?, name: String, into directory: URL) throws {
        for dark in [true, false] {
            let host = NSHostingView(rootView: AnyView(view))
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let bounds: CGRect
            if let size {
                host.layoutSubtreeIfNeeded()
                bounds = CGRect(origin: .zero, size: size)
            } else {
                bounds = CGRect(origin: .zero, size: HistoryPopover.settledFittingSize(of: host))
            }
            host.frame = bounds
            host.layoutSubtreeIfNeeded()

            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: bounds),
                                    "\(name): the view has no backing to cache")
            host.cacheDisplay(in: bounds, to: rep)

            let png = try XCTUnwrap(Self.onePointPerPixel(rep, size: bounds.size).representation(using: .png, properties: [:]),
                                    "\(name): PNG encoding failed")
            try png.write(to: directory.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
        }
    }

    /// The cached rep comes back at the screen's backing scale, which on a
    /// Retina Mac quadruples the pixels — and the file size — for no gain in a
    /// README. Redraw it at one pixel per point when it is not already there.
    private static func onePointPerPixel(_ rep: NSBitmapImageRep, size: CGSize) -> NSBitmapImageRep {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard rep.pixelsWide != width || rep.pixelsHigh != height,
              let target = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return rep }
        target.size = size

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: target)
        NSGraphicsContext.current?.imageInterpolation = .high
        rep.draw(in: CGRect(origin: .zero, size: size))
        return target
    }

    // MARK: - Environment

    private func outputDirectory() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["SAYVOICE_RENDER_DIR"], !path.isEmpty else {
            throw XCTSkip("SAYVOICE_RENDER_DIR not set")
        }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// An empty models directory, so the rows look the same on any Mac whether
    /// or not models are installed.
    private func temporaryModelsDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SayVoiceShots-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
