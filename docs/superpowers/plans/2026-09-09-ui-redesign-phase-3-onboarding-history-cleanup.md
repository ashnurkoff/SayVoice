# UI Redesign — Phase 3: Onboarding, History, Menu Bar, Cleanup, Translation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Dispatch in batches:** one implementer per batch (A, B, C, D), one review per batch.

**Goal:** Finish the redesign: the four-step onboarding on the design system, the history popover and static menu-bar icons, the repository cleanup (generated project out of git, README, screenshot harness), the remaining deferred polish, and the translation of every remaining Russian string and comment — so the owner can do one clean install and test everything.

**Architecture:** Onboarding becomes a small `@Observable` model plus one view per step, reusing `ModelRow`/`DownloadProgress`/`ModelDownloads`/`HotkeyRecorder`. History becomes `Features/History/` with a pure filter and a coarse relative-time formatter, on top of a new `EmptyState` component. The menu bar moves to `Features/MenuBar/` with static state icons. Screenshots are rendered by a test-target harness driven by `Scripts/render-surfaces`. Translation is a mechanical last batch guarded by a Cyrillic grep.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI + AppKit, macOS 26, XcodeGen 2.46, XCTest. Phase 1–2 tokens and components are in the tree.

**Spec:** `docs/superpowers/specs/2026-09-09-ui-redesign-design.md` — §5.3 (onboarding), §5.4 (history), §5.6 (menu bar), §6 (architecture), §7 (removals), §8 (language), §9 (tests/screenshots). Phase 2 plan: `docs/superpowers/plans/2026-09-09-ui-redesign-phase-2-settings.md` (head `12299fa`).

## Global Constraints

- Deployment target **macOS 26.0**; no `#available`. Swift 6 strict concurrency; zero warnings from touched files.
- **Everything created or rewritten is in English.** After Batch D, `grep -rn "[А-Яа-яЁё]" SayVoice Tests Scripts project.yml .gitignore` returns only the language endonyms in the Recognition picker.
- **No third-party libraries.** `DesignSystem/` never references feature or app types.
- Colours only through `DS.Colors.*`; fonts only through `DS.font(_:)`. Three-places accent rule (orb/logo; active or interactive control; overlay glass). The onboarding art panel is the logo place: `accent → accent2` gradient with a white waveform.
- Windows only through `AppWindow.make` / `AppWindow.present`.
- Commit after every task; English, imperative; **no AI-attribution trailers**.
- `xcodegen generate` after adding/moving/deleting files; commit the regenerated project **until Batch C removes it from git**; after that, `xcodegen generate` is a local step and `SayVoice.xcodeproj/` is ignored.
- Build: `xcodebuild -project SayVoice.xcodeproj -scheme SayVoice -configuration Release -derivedDataPath build build 2>&1 | grep -E "error:|BUILD"`
- Test: `xcodebuild -project SayVoice.xcodeproj -scheme SayVoice -derivedDataPath build test 2>&1 | grep -E "error:|Executed|failed|passed" | tail -5`
- **No installs to /Applications and no launching the app.** The owner installs once after the whole redesign.

---

## File structure

**Created**

| Path | Responsibility |
|---|---|
| `SayVoice/DesignSystem/Components/EmptyState.swift` | Symbol + title + hint block for empty lists |
| `SayVoice/Features/Onboarding/OnboardingModel.swift` | Step state machine, permission polling, completion |
| `SayVoice/Features/Onboarding/OnboardingView.swift` | 640 × 360 window root: `ArtPanel` + current step |
| `SayVoice/Features/Onboarding/ArtPanel.swift` | 240-wide gradient panel with waveform and progress dots |
| `SayVoice/Features/Onboarding/WelcomeStep.swift`, `PermissionsStep.swift`, `ModelStep.swift`, `HotkeyStep.swift` | One view per step |
| `SayVoice/Features/History/HistoryPopover.swift` | 320-wide popover: header, search, list, footer |
| `SayVoice/Features/History/HistoryRow.swift` | One entry: 2-line text, meta line, hover Copy |
| `SayVoice/Features/History/HistoryFilter.swift` | Pure search filter |
| `SayVoice/Features/History/RelativeTime.swift` | Coarse relative-time formatter |
| `SayVoice/Features/MenuBar/MenuBarController.swift` | Moved from `UI/`, English, static icons, About item |
| `SayVoice/Features/MenuBar/StatusIcon.swift` | Icon per `AppState` |
| `Scripts/render-surfaces` | Shell wrapper: runs the screenshot harness, writes `docs/screenshots/` |
| `Tests/SayVoiceTests/SurfaceScreenshotTests.swift` | Renders every surface in both themes when `SAYVOICE_RENDER_DIR` is set |
| `README.md` | Build, install, models, licences, structure |
| `Tests/SayVoiceTests/OnboardingTests.swift`, `HistoryTests.swift`, `MenuBarTests.swift` | See tasks |

**Modified:** `AppCoordinator.swift` (onboarding via `AppWindow`, `onShowAbout`, `MenuBarController(status:)`), `ModelManager.swift` (delete fraction wrapper, `badge`, `fileSize`), `SettingsStore.swift`, `HotkeyListener/*`, `Audio/*`, `Transcription/*`, `TextInjection/*`, `Permissions/*`, `History/*`, `App/*` (translation), `.gitignore`, `project.yml`, spec §6/§9/§10, phase-1 ledger minors (`Colors.swift`, `Buttons.swift`, `SilenceTrimmerTests.swift`).

**Deleted:** `SayVoice/UI/OnboardingView.swift`, `SayVoice/UI/HistoryPopoverView.swift`, `SayVoice/UI/MenuBarController.swift` (moved), the `SayVoice/UI/` directory, `SayVoice.xcodeproj` from git.

---

# Batch A — Onboarding

### Task A1: `OnboardingModel` and the four steps

**Files:**
- Create: `SayVoice/Features/Onboarding/OnboardingModel.swift`, `ArtPanel.swift`, `WelcomeStep.swift`, `PermissionsStep.swift`, `ModelStep.swift`, `HotkeyStep.swift`, `OnboardingView.swift`
- Modify: `SayVoice/App/AppCoordinator.swift` (`showOnboardingWindow`)
- Modify: `SayVoice/ModelManagement/ModelManager.swift` (delete `downloadModel(_:)`, `badge`, `fileSize`)
- Delete: `SayVoice/UI/OnboardingView.swift`
- Test: `Tests/SayVoiceTests/OnboardingTests.swift`

**Interfaces:**
- Produces: `enum OnboardingStep: Int, CaseIterable { welcome, permissions, model, hotkey }`; `@MainActor @Observable final class OnboardingModel { init(permissions: PermissionManager, settings: SettingsStore, modelManager: ModelManager, downloads: ModelDownloads, onFinished: @escaping () -> Void); var step; var microphoneGranted: Bool; var accessibilityGranted: Bool; var canContinue: Bool; func next(); func skip(); func requestMicrophone(); func openAccessibility(); func startPolling(); func stopPolling() }`; `OnboardingView(model:onHotkeyChanged:onHotkeyModeChanged:)` with `static let windowSize = NSSize(width: 640, height: 360)`.
- Consumes: `PermissionManager.isMicrophoneGranted/requestMicrophone()/openMicrophoneSettings()/isAccessibilityGranted/requestAccessibilityPrompt()/openAccessibilitySettings()/resetAccessibilityEntry()`, `ModelDownloads`, `ModelRow`, `DownloadProgress`, `HotkeyRecorder`, `LogoMark` (from `SettingsRail.swift`), `Waveform`.

- [ ] **Step 1: Failing tests**

```swift
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
}
```

`PermissionSource` is a protocol introduced by this task so the model is testable without TCC:

```swift
/// What onboarding needs from the permission layer; `PermissionManager` conforms.
@MainActor
protocol PermissionSource: AnyObject {
    var isMicrophoneGranted: Bool { get }
    var isAccessibilityGranted: Bool { get }
    func requestMicrophone() async -> Bool
    func openMicrophoneSettings()
    func requestAccessibilityPrompt()
    func openAccessibilitySettings()
}
extension PermissionManager: PermissionSource {}
```

(`isAccessibilityGranted` and `requestAccessibilityPrompt` are `nonisolated` on `PermissionManager`; a nonisolated member satisfies a main-actor protocol requirement, so the extension is empty. Put the protocol in `OnboardingModel.swift`.)

- [ ] **Step 2: Run to verify failure** — `cannot find 'OnboardingModel'`.

- [ ] **Step 3: `OnboardingModel.swift`**

```swift
import Foundation

enum OnboardingStep: Int, CaseIterable {
    case welcome, permissions, model, hotkey

    var title: String {
        switch self {
        case .welcome:     return "Welcome"
        case .permissions: return "Permissions"
        case .model:       return "Model"
        case .hotkey:      return "Hotkey"
        }
    }
}

/// Step state machine for first run. Permissions cannot be skipped — the app
/// does not work without them. Model and hotkey can.
@MainActor @Observable
final class OnboardingModel {
    let permissions: PermissionSource
    let settings: SettingsStore
    let modelManager: ModelManager
    let downloads: ModelDownloads
    private let onFinished: () -> Void

    var step: OnboardingStep = .welcome
    var microphoneGranted = false
    var accessibilityGranted = false
    private var pollTask: Task<Void, Never>?

    init(permissions: PermissionSource, settings: SettingsStore, modelManager: ModelManager,
         downloads: ModelDownloads, onFinished: @escaping () -> Void) {
        self.permissions = permissions
        self.settings = settings
        self.modelManager = modelManager
        self.downloads = downloads
        self.onFinished = onFinished
        refreshPermissions()
    }

    var canSkip: Bool { step == .model || step == .hotkey }

    var canContinue: Bool {
        step != .permissions || (microphoneGranted && accessibilityGranted)
    }

    /// The three models offered on first run (spec §5.3); the full list lives in Settings.
    static let offeredModels: [ModelManager.ModelSize] = [.turboQ5, .small, .turboQ8]

    func next() {
        guard canContinue else { return }
        advance()
    }

    func skip() {
        guard canSkip else { return }
        advance()
    }

    private func advance() {
        if let following = OnboardingStep(rawValue: step.rawValue + 1) {
            step = following
        } else {
            stopPolling()
            onFinished()
        }
    }

    // MARK: Permissions

    func refreshPermissions() {
        microphoneGranted = permissions.isMicrophoneGranted
        accessibilityGranted = permissions.isAccessibilityGranted
    }

    func requestMicrophone() {
        Task {
            microphoneGranted = await permissions.requestMicrophone()
            if !microphoneGranted { permissions.openMicrophoneSettings() }
        }
    }

    func openAccessibility() {
        permissions.requestAccessibilityPrompt()
        permissions.openAccessibilitySettings()
    }

    /// Accessibility has no callback; poll once a second while the step is visible.
    func startPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.refreshPermissions()
                if self.microphoneGranted && self.accessibilityGranted { return }
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}
```

- [ ] **Step 4: `ArtPanel.swift`**

```swift
import SwiftUI

/// Left panel of the onboarding window: the brand gradient, a large white
/// waveform and one dot per step. The one place besides the orb and the logo
/// mark where the accent gradient is allowed.
struct ArtPanel: View {
    static let width: CGFloat = 240
    let step: OnboardingStep

    var body: some View {
        ZStack {
            LinearGradient(colors: [DS.Colors.accent.color, DS.Colors.accent2.color],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: DS.Space.s24) {
                Spacer(minLength: 0)
                Image(systemName: "waveform")
                    .font(.system(size: 88, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                Text("SayVoice")
                    .font(DS.font(.title))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    ForEach(OnboardingStep.allCases, id: \.self) { s in
                        Capsule()
                            .fill(.white.opacity(s == step ? 0.95 : 0.35))
                            .frame(width: s == step ? 18 : 6, height: 6)
                    }
                }
                .padding(.bottom, DS.Space.s20)
                .animation(DS.Motion.stateChange, value: step)
            }
        }
        .frame(width: Self.width)
        .accessibilityHidden(true)
    }
}
```

- [ ] **Step 5: Steps**

`WelcomeStep.swift`:

```swift
import SwiftUI

struct WelcomeStep: View {
    let onNext: () -> Void

    var body: some View {
        StepLayout(title: "Speak. It types.",
                   subtitle: "Hold a key, talk, release — the words land where your cursor is. Recognition runs on this Mac; nothing leaves it.") {
            EmptyView()
        } footer: {
            Button("Get started", action: onNext).buttonStyle(.dsPrimary)
        }
    }
}

/// Shared step frame: title, subtitle, content, footer row. Used by all four steps.
struct StepLayout<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                Text(title).font(DS.font(.section)).foregroundStyle(DS.Colors.text.color)
                Text(subtitle).font(DS.font(.body)).foregroundStyle(DS.Colors.muted.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
            Spacer(minLength: 0)
            HStack(spacing: DS.Space.s12) { Spacer(minLength: 0); footer() }
        }
        .padding(DS.Space.s28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
```

`PermissionsStep.swift`:

```swift
import SwiftUI

struct PermissionsStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        StepLayout(title: "Two permissions",
                   subtitle: "Microphone to hear you; Accessibility for the global hotkey and to insert text.") {
            Card {
                PermissionRow(name: "Microphone", granted: model.microphoneGranted,
                              actionTitle: "Allow", action: model.requestMicrophone)
                PermissionRow(name: "Accessibility", granted: model.accessibilityGranted,
                              actionTitle: "Open System Settings", action: model.openAccessibility)
            }
        } footer: {
            Button("Continue", action: model.next).buttonStyle(.dsPrimary).disabled(!model.canContinue)
        }
        .onAppear { model.refreshPermissions(); model.startPolling() }
        .onDisappear { model.stopPolling() }
    }
}

private struct PermissionRow: View {
    let name: String
    let granted: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        SettingsRow(name, note: granted ? "Granted" : "Not yet") {
            if granted {
                Chip("granted", style: .ok)
            } else {
                Button(actionTitle, action: action).buttonStyle(.dsSecondary)
            }
        }
    }
}
```

`ModelStep.swift`:

```swift
import SwiftUI

struct ModelStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        StepLayout(title: "Pick a model",
                   subtitle: "Large Turbo Q5 is the sweet spot. All five models are in Settings → Recognition.") {
            VStack(spacing: DS.Space.s8) {
                ForEach(OnboardingModel.offeredModels, id: \.self) { size in
                    ModelRow(
                        name: size.displayName,
                        badge: size == .recommended ? "recommended" : nil,
                        badgeIsAccent: size == .recommended,
                        qualitySteps: size.qualitySteps,
                        sizeText: size.sizeText,
                        isSelected: model.settings.modelSize == size.settingsString,
                        isDownloaded: model.modelManager.isModelAvailable(size),
                        download: model.downloads.state(for: size),
                        onSelect: { model.settings.modelSize = size.settingsString },
                        onDownload: { model.downloads.start(size) },
                        onCancel: { model.downloads.cancel(size) },
                        onRetry: { model.downloads.start(size) }
                    )
                }
            }
        } footer: {
            Button("Download later", action: model.skip).buttonStyle(.dsLink)
            Button("Continue", action: model.next).buttonStyle(.dsPrimary)
        }
    }
}
```

`HotkeyStep.swift`:

```swift
import SwiftUI

struct HotkeyStep: View {
    @Bindable var model: OnboardingModel
    var onHotkeyChanged: ((Hotkey) -> Void)?
    var onHotkeyModeChanged: ((Bool) -> Void)?

    var body: some View {
        StepLayout(title: "Your hotkey",
                   subtitle: "Right ⌥ works out of the box. Change it here or later in Settings.") {
            Card {
                SettingsRow("Hotkey") {
                    HotkeyRecorder(hotkey: $model.settings.hotkey, onChange: onHotkeyChanged)
                }
                SettingsRow("Mode", note: model.settings.hotkeyIsToggle ? "Press once to start, again to stop." : "Recording runs while the key is held.") {
                    Picker("", selection: $model.settings.hotkeyMode) {
                        Text("Hold").tag("hold")
                        Text("Toggle").tag("toggle")
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 180)
                    .onChange(of: model.settings.hotkeyMode) { _, new in onHotkeyModeChanged?(new == "toggle") }
                }
            }
        } footer: {
            Button("Skip", action: model.skip).buttonStyle(.dsLink)
            Button("Finish", action: model.next).buttonStyle(.dsPrimary)
        }
    }
}
```

`OnboardingView.swift`:

```swift
import AppKit
import SwiftUI

/// First-run window: art panel on the left, one step at a time on the right.
struct OnboardingView: View {
    static let windowSize = NSSize(width: 640, height: 360)

    let model: OnboardingModel
    var onHotkeyChanged: ((Hotkey) -> Void)?
    var onHotkeyModeChanged: ((Bool) -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            ArtPanel(step: model.step)
            Group {
                switch model.step {
                case .welcome:     WelcomeStep(onNext: model.next)
                case .permissions: PermissionsStep(model: model)
                case .model:       ModelStep(model: model)
                case .hotkey:      HotkeyStep(model: model, onHotkeyChanged: onHotkeyChanged, onHotkeyModeChanged: onHotkeyModeChanged)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(DS.Motion.stateChange, value: model.step)
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .background(DS.Colors.ground.color)
        .font(DS.font(.body))
    }
}
```

`@Bindable var model: OnboardingModel` then `$model.settings.hotkey` — `settings` is a `let` reference to an `@Observable` class, so derive the binding through a nested `@Bindable`: inside the step body write `@Bindable var settings = model.settings` as a local and use `$settings.hotkey` / `$settings.hotkeyMode`. Do the same in `ModelStep` if a binding is needed (it is not).

- [ ] **Step 6: Coordinator and catalogue**

`AppCoordinator.showOnboardingWindow()` becomes:

```swift
    private func showOnboardingWindow() {
        let model = OnboardingModel(
            permissions: permissionManager, settings: settingsStore,
            modelManager: modelManager, downloads: modelDownloads,
            onFinished: { [weak self] in
                guard let self else { return }
                self.settingsStore.hasCompletedOnboarding = true
                self.onboardingWindow?.close()
                self.onboardingWindow = nil
                print("[SayVoice] Onboarding complete — starting normal flow")
                self.startHotkeyAndPermissions()
            }
        )
        let view = OnboardingView(
            model: model,
            onHotkeyChanged: { [weak self] hotkey in self?.hotkeyListener?.apply(hotkey) },
            onHotkeyModeChanged: { [weak self] isToggle in self?.hotkeyListener?.apply(isToggle: isToggle) }
        )
        let window = AppWindow.make(title: "Welcome to SayVoice", size: OnboardingView.windowSize, content: view)
        AppWindow.present(window)
        onboardingWindow = window
    }
```

The old `resetAccessibilityEntry()` call that the deleted step made on appear moves to the coordinator: before showing onboarding, `if !permissionManager.isAccessibilityGranted { permissionManager.resetAccessibilityEntry() }` (same rule the normal startup path already uses).

`ModelManager.swift`: delete `downloadModel(_:)` (the fraction wrapper), `ModelSize.badge` and `ModelSize.fileSize`; `sizeText` keeps the numbers. Run `grep -rn "fileSize\|\.badge\|downloadModel(" SayVoice Tests` — must return only `downloadModelProgress`.

Delete `SayVoice/UI/OnboardingView.swift` (`git rm`).

- [ ] **Step 7: Generate, build, test — expect PASS** (56 + 5 = 61 tests).

- [ ] **Step 8: Commit** — `Rebuild onboarding on the design system: four steps, art panel, shared download coordinator`

---

# Batch B — History popover, menu bar, EmptyState

### Task B1: `EmptyState`, `RelativeTime`, `HistoryFilter`

**Files:**
- Create: `SayVoice/DesignSystem/Components/EmptyState.swift`, `SayVoice/Features/History/RelativeTime.swift`, `SayVoice/Features/History/HistoryFilter.swift`
- Test: `Tests/SayVoiceTests/HistoryTests.swift` (part 1)

**Interfaces:**
- Produces: `EmptyState(symbol: String, title: String, hint: String)`; `enum RelativeTime { static func coarse(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String }`; `enum HistoryFilter { static func apply(_ entries: [TranscriptionEntry], query: String) -> [TranscriptionEntry] }`.

- [ ] **Step 1: Failing tests**

```swift
import SwiftUI
import XCTest
@testable import SayVoice

final class HistoryTests: XCTestCase {

    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)   // a fixed instant

    func testCoarseRelativeTime() {
        let cal = Calendar(identifier: .gregorian)
        XCTAssertEqual(RelativeTime.coarse(now.addingTimeInterval(-20), now: now, calendar: cal), "just now")
        XCTAssertEqual(RelativeTime.coarse(now.addingTimeInterval(-5 * 60), now: now, calendar: cal), "5 min")
        XCTAssertEqual(RelativeTime.coarse(now.addingTimeInterval(-3 * 3600), now: now, calendar: cal), "3 h")
        XCTAssertEqual(RelativeTime.coarse(cal.date(byAdding: .day, value: -1, to: now)!, now: now, calendar: cal), "yesterday")
        XCTAssertEqual(RelativeTime.coarse(cal.date(byAdding: .day, value: -4, to: now)!, now: now, calendar: cal), "4 d")
        let old = cal.date(byAdding: .day, value: -40, to: now)!
        XCTAssertEqual(RelativeTime.coarse(old, now: now, calendar: cal), old.formatted(.dateTime.day().month(.abbreviated)))
    }

    func testFilterIsCaseInsensitiveSubstringAndKeepsOrder() {
        let e = [TranscriptionEntry(text: "Deploy the API tonight", durationSeconds: 2),
                 TranscriptionEntry(text: "buy milk", durationSeconds: 1),
                 TranscriptionEntry(text: "api keys rotated", durationSeconds: 3)]
        XCTAssertEqual(HistoryFilter.apply(e, query: "").map(\.text), e.map(\.text))
        XCTAssertEqual(HistoryFilter.apply(e, query: "  api ").map(\.text), ["Deploy the API tonight", "api keys rotated"])
        XCTAssertEqual(HistoryFilter.apply(e, query: "zzz"), [])
    }

    @MainActor
    func testEmptyStateRenders() {
        for dark in [true, false] {
            let host = NSHostingView(rootView: EmptyState(symbol: "waveform", title: "No dictations yet", hint: "Hold Right ⌥ and speak."))
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            host.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
            host.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(host.fittingSize.height, 60)
        }
    }
}
```

`TranscriptionEntry` must be `Equatable` for the empty-result assertion — add `Equatable` to its conformance list (fields are all `Equatable`).

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement**

`EmptyState.swift`:

```swift
import SwiftUI

/// Centered symbol, title and hint for an empty list. Neutral colours only.
struct EmptyState: View {
    let symbol: String
    let title: String
    let hint: String

    var body: some View {
        VStack(spacing: DS.Space.s8) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(DS.Colors.faint.color)
            Text(title).font(DS.font(.bodyMedium)).foregroundStyle(DS.Colors.text.color)
            Text(hint).font(DS.font(.caption)).foregroundStyle(DS.Colors.muted.color)
                .multilineTextAlignment(.center)
        }
        .padding(DS.Space.s24)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
```

`RelativeTime.swift`:

```swift
import Foundation

/// Coarse relative time for list meta lines: "just now", "5 min", "3 h",
/// "yesterday", "4 d", then a short date. Deliberately imprecise — the
/// popover is a glance, not a log.
enum RelativeTime {
    static func coarse(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min" }
        if seconds < 24 * 3600, calendar.isDate(date, inSameDayAs: now) || seconds < 6 * 3600 {
            return "\(Int(seconds / 3600)) h"
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days <= 1 { return "yesterday" }
        if days < 7 { return "\(days) d" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
```

`HistoryFilter.swift`:

```swift
import Foundation

enum HistoryFilter {
    /// Case-insensitive substring match on the text; blank query returns everything.
    static func apply(_ entries: [TranscriptionEntry], query: String) -> [TranscriptionEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return entries }
        return entries.filter { $0.text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}
```

- [ ] **Step 4: Generate, build, test — PASS.**
- [ ] **Step 5: Commit** — `Add EmptyState, coarse relative time and the history filter`

### Task B2: `HistoryPopover` + `HistoryRow`

**Files:**
- Create: `SayVoice/Features/History/HistoryPopover.swift`, `HistoryRow.swift`
- Test: append to `HistoryTests.swift`

**Interfaces:**
- Produces: `HistoryPopover(entries: [TranscriptionEntry], status: AppStatus, hotkeyName: String, onClear: @escaping () -> Void, onSettings: @escaping () -> Void)`; `static let width: CGFloat = 320`.
- Consumes: `LogoMark`, `StatusPill` (both in `Features/Settings/`), `EmptyState`, `RelativeTime`, `HistoryFilter`.

- [ ] **Step 1: Failing test**

```swift
    @MainActor
    func testHistoryPopoverRendersEmptyAndFilled() {
        let status = AppStatus(); status.modelName = "Large Turbo Q5"
        let entries = (0..<3).map { TranscriptionEntry(text: "Entry \($0) with enough words to wrap onto a second line in the popover", durationSeconds: 4.2, language: "en") }
        for list in [[], entries] {
            for dark in [true, false] {
                let host = NSHostingView(rootView: HistoryPopover(entries: list, status: status, hotkeyName: "Right ⌥", onClear: {}, onSettings: {}))
                host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                host.layoutSubtreeIfNeeded()
                let s = host.fittingSize
                XCTAssertEqual(s.width, HistoryPopover.width, accuracy: 0.5)
                XCTAssertGreaterThan(s.height, list.isEmpty ? 120 : 200)
                XCTAssertLessThanOrEqual(s.height, 520)
            }
        }
    }
```

- [ ] **Step 2: Implement**

`HistoryRow.swift`:

```swift
import AppKit
import SwiftUI

/// One dictation: two-line text, meta line, Copy on hover → "Copied".
struct HistoryRow: View {
    let entry: TranscriptionEntry
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.s8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.text)
                    .font(DS.font(.body)).foregroundStyle(DS.Colors.text.color)
                    .lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: DS.Space.s8) {
                    Text(RelativeTime.coarse(entry.date))
                    Text(String(format: "%.1f s", entry.durationSeconds))
                    if let lang = entry.language { Chip(lang.uppercased()) }
                }
                .font(DS.font(.valueSmall)).foregroundStyle(DS.Colors.muted.color)
            }
            Spacer(minLength: 0)
            if copied {
                Chip("copied", style: .ok)
            } else if hovering {
                Button("Copy", action: copy).buttonStyle(.dsLink)
            }
        }
        .padding(.horizontal, DS.Space.s12)
        .padding(.vertical, DS.Space.s8)
        .frame(minHeight: DS.Size.popoverRow)
        .contentShape(Rectangle())
        .background(RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
            .fill(hovering ? DS.Colors.surface2.color : Color.clear))
        .onHover { hovering = $0 }
        .animation(DS.Motion.stateChange, value: hovering)
        .animation(DS.Motion.stateChange, value: copied)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Copy", copy)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}
```

`HistoryPopover.swift`:

```swift
import SwiftUI

/// Menu-bar popover: header with logo and status, search, recent dictations,
/// footer with Clear… and Settings. Width 320.
struct HistoryPopover: View {
    static let width: CGFloat = 320
    static let listMaxHeight: CGFloat = 360

    let entries: [TranscriptionEntry]
    let status: AppStatus
    let hotkeyName: String
    let onClear: () -> Void
    let onSettings: () -> Void

    @State private var query = ""
    @State private var confirmingClear = false

    private var shown: [TranscriptionEntry] { HistoryFilter.apply(entries, query: query) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.s8) {
                LogoMark(size: 22)
                Text("SayVoice").font(DS.font(.bodyMedium)).foregroundStyle(DS.Colors.text.color)
                Spacer(minLength: DS.Space.s8)
                StatusPill(status: status)
            }
            .padding(.horizontal, DS.Space.s12).padding(.vertical, DS.Space.s12)

            if !entries.isEmpty {
                TextField("Search", text: $query)
                    .textFieldStyle(.plain)
                    .font(DS.font(.body))
                    .padding(.horizontal, DS.Space.s12).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous).fill(DS.Colors.surface2.color))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous).strokeBorder(DS.Colors.line.color, lineWidth: 1))
                    .padding(.horizontal, DS.Space.s12).padding(.bottom, DS.Space.s8)
            }

            Rectangle().fill(DS.Colors.line.color).frame(height: 1)

            if entries.isEmpty {
                EmptyState(symbol: "waveform", title: "No dictations yet", hint: "Hold \(hotkeyName) and speak — the text lands where your cursor is.")
            } else if shown.isEmpty {
                EmptyState(symbol: "magnifyingglass", title: "Nothing matches", hint: "Try another word.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(shown) { HistoryRow(entry: $0) }
                    }
                    .padding(DS.Space.s4)
                }
                .frame(maxHeight: Self.listMaxHeight)
            }

            Rectangle().fill(DS.Colors.line.color).frame(height: 1)

            HStack {
                if !entries.isEmpty {
                    Button("Clear…") { confirmingClear = true }.buttonStyle(.dsDestructive)
                        .confirmationDialog("Clear all dictations?", isPresented: $confirmingClear, titleVisibility: .visible) {
                            Button("Clear", role: .destructive, action: onClear)
                        } message: { Text("This removes the local history. Nothing else is affected.") }
                }
                Spacer(minLength: DS.Space.s8)
                Button("Settings", action: onSettings).buttonStyle(.dsSecondary)
            }
            .padding(.horizontal, DS.Space.s12).padding(.vertical, DS.Space.s8)
        }
        .frame(width: Self.width)
        .background(DS.Colors.ground.color)
        .font(DS.font(.body))
    }
}
```

If `.dsDestructive` does not exist under that name in `Buttons.swift`, use the destructive style that does and note it.

- [ ] **Step 3: Generate, build, test — PASS.**
- [ ] **Step 4: Commit** — `Add the history popover with search, hover copy and confirmed clear`

### Task B3: Menu bar — move, static icons, About item; delete old UI

**Files:**
- Move: `SayVoice/UI/MenuBarController.swift` → `SayVoice/Features/MenuBar/MenuBarController.swift` (rewritten in English)
- Create: `SayVoice/Features/MenuBar/StatusIcon.swift`
- Modify: `SayVoice/App/AppCoordinator.swift` (init with `status`, `onShowAbout`, hotkey name for the popover)
- Delete: `SayVoice/UI/HistoryPopoverView.swift`; the `SayVoice/UI/` directory
- Test: `Tests/SayVoiceTests/MenuBarTests.swift`

**Interfaces:**
- Produces: `enum StatusIcon { @MainActor static func image(for state: AppState, appearance: NSAppearance) -> NSImage }`; `MenuBarController(status: AppStatus)` with `onShowSettings`, `onShowAbout`, `onQuit`, `onClearHistory`, `onPopoverWillShow`, `historyEntries`, `hotkeyName: String`, `showHistory()`, `setState(_:)`.

- [ ] **Step 1: Failing test**

```swift
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
```

- [ ] **Step 2: `StatusIcon.swift`**

```swift
import AppKit

/// Menu-bar icon per state. Idle and error are template glyphs (the system
/// tints them); recording and transcribing draw a coloured dot, so they are
/// not templates. No animation: the menu bar speaks the orb's state language.
enum StatusIcon {
    private static let pointSize: CGFloat = 16

    @MainActor
    static func image(for state: AppState, appearance: NSAppearance) -> NSImage {
        switch state {
        case .idle:
            return glyph("mic.fill", description: "SayVoice")
        case .recording:
            return micWithDot(DS.Colors.rec.resolved(for: appearance), description: "Recording")
        case .transcribing, .injecting:
            return micWithDot(DS.Colors.accent.resolved(for: appearance), description: "Transcribing")
        case .error:
            return glyph("exclamationmark.triangle", description: "Needs attention")
        }
    }

    private static func glyph(_ name: String, description: String) -> NSImage {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: description)!
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .regular))!
        img.isTemplate = true
        return img
    }

    private static func micWithDot(_ dot: NSColor, description: String) -> NSImage {
        let size = NSSize(width: 21, height: 21)
        let img = NSImage(size: size, flipped: false) { rect in
            let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
                .applying(.init(paletteColors: [.labelColor]))
            if let mic = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                let origin = NSPoint(x: (rect.width - mic.size.width) / 2, y: (rect.height - mic.size.height) / 2)
                mic.draw(in: NSRect(origin: origin, size: mic.size))
            }
            let d: CGFloat = 6.5
            dot.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.maxX - d, y: rect.maxY - d, width: d, height: d)).fill()
            return true
        }
        img.isTemplate = false
        img.accessibilityDescription = description
        return img
    }
}
```

`DSColor.resolved(for:)` returns `NSColor` (Phase 1). If its signature differs, use it as defined and note it.

- [ ] **Step 3: `MenuBarController.swift`** — `git mv` then rewrite: all comments English; `init(status: AppStatus)`; `setupMenu()` items "Settings…" (⌘,), "About SayVoice" → `onShowAbout`, separator, "Quit SayVoice" (⌘Q); no download item; `setState(_:)` sets `button.image = StatusIcon.image(for: state, appearance: button.effectiveAppearance)` and nothing else (delete the timer, `animationFrame`, `startPulseAnimation`, `stopAnimation`, `idleIcon/recordingIcon/statusIcon`); `showHistory()` and `refreshPopoverContent()` build `HistoryPopover(entries: historyEntries, status: status, hotkeyName: hotkeyName, onClear:…, onSettings:…)`; `popover.contentSize = NSSize(width: HistoryPopover.width, height: 420)`. Keep the right-click/left-click handling and the "Show all" entry point.

Coordinator: `menuBarController = MenuBarController(status: status)`; `menuBarController?.onShowAbout = { [weak self] in self?.showSettings(section: .system) }`; set `menuBarController?.hotkeyName = settingsStore.hotkey.displayName` in `start()` and again in `onHotkeyChanged` (settings and onboarding closures). `git rm SayVoice/UI/HistoryPopoverView.swift`; the `UI` directory must be empty and gone.

- [ ] **Step 4: Generate, build, test — PASS.** `grep -rn "HistoryPopoverView\|SayVoice/UI\|animationTimer\|Скачать\|Настройки" SayVoice Tests` → nothing.
- [ ] **Step 5: Commit** — `Move the menu bar into Features, use static state icons, add About; remove the old popover`

---

# Batch C — Repository cleanup, screenshots, deferred polish, spec

### Task C1: Generated project out of git, README, gitignore

- [ ] `git rm -r --cached SayVoice.xcodeproj`; `.gitignore` gains `SayVoice.xcodeproj/` and all its comments become English (`# Build artefacts`, `# Whisper models are not stored in the repository…`, etc.).
- [ ] `README.md` (English) with sections: What it is (one paragraph, offline, menu bar, macOS 26+); Requirements (macOS 26, Xcode 26, XcodeGen); Build (`brew install xcodegen`, `xcodegen generate`, open or `xcodebuild`), Install (copy `build/Build/Products/Release/SayVoice.app` to /Applications; first-run permissions); Models (downloaded into `~/Library/Application Support/SayVoice/Models`, list of five with sizes from `sizeText`); Project layout (the §6 tree); Tests (`xcodebuild … test`); Screenshots (`Scripts/render-surfaces`); Licences (MIT for SayVoice — add `LICENSE` file with MIT, copyright 2026 Aleksandr Shnurkov; whisper.cpp MIT; Onest and JetBrains Mono OFL). Screenshots referenced as `docs/screenshots/*.png` (produced in C2).
- [ ] Commit — `Stop tracking the generated Xcode project; add README and LICENSE`

### Task C2: Screenshot harness

**Files:** `Tests/SayVoiceTests/SurfaceScreenshotTests.swift`, `Scripts/render-surfaces` (executable), `docs/screenshots/*.png`, spec §9 amendment.

- [ ] Test class: skipped unless `ProcessInfo.processInfo.environment["SAYVOICE_RENDER_DIR"]` is set; renders each surface in both appearances with the offline renderer (`NSHostingView` → `bitmapImageRepForCachingDisplay` → PNG; `performAsCurrentDrawingAppearance` for dynamic colours — the Phase 1 renderer): overlay recording/transcribing/result/error (via `OverlayModel` + `OverlayView`), settings ×5 sections, onboarding ×4 steps, history empty/filled. File names `<surface>-<theme>.png`. Header comment documents the known limits (glass as flat fill; prominent buttons render inactive).
- [ ] `Scripts/render-surfaces`: `#!/bin/sh`, `set -e`, `xcodegen generate` if the project is missing, then `SAYVOICE_RENDER_DIR="$PWD/docs/screenshots" xcodebuild -project SayVoice.xcodeproj -scheme SayVoice -derivedDataPath build test -only-testing:SayVoiceTests/SurfaceScreenshotTests`.
- [ ] Run it; commit the PNGs. Spec §9: replace the `Scripts/render-surfaces` bullet with "a test-target harness (`SurfaceScreenshotTests`) driven by `Scripts/render-surfaces`".
- [ ] Commit — `Add the screenshot harness and generated surface screenshots`

### Task C3: Deferred minors and spec alignment

- [ ] `DSColor`: cache the `NSColor` per token (`static let` colours already; make `color` a stored `let` built once in `init` rather than per access) — only if the current implementation rebuilds on each access; verify with a read first.
- [ ] `.white` literals in `Orb`/`LogoMark`/`ArtPanel` → new token `DS.Colors.onAccent` (white in both themes); spec §3.1 row.
- [ ] `SilenceTrimmerTests`: seed the generator (`var g = SeededGenerator(seed: 42)` — a small `RandomNumberGenerator` in the test file).
- [ ] `DS.Radius.control + 2` occurrences → `DS.Radius.row` where that is what is meant, else a named token.
- [ ] Spec §6 tree = the actual tree (`Features/Onboarding`, `Features/History`, `Features/MenuBar`, `Resources/Licenses`); §7 table rows all satisfied (tick them off in the report); §10: replace "Each stage ends with a build, an install, a live check and a commit." with "Each stage ends with a build, the test suite and a commit; the owner installs once at the end of the redesign and runs the live checks listed in the final report."
- [ ] Carried from the phase 2 final re-review: `SettingsRow` accessibility → `.accessibilityElement(children: .contain)` with `.accessibilityLabel(label)` on the control slot (pickers keep per-segment access); `ModelDownloads.cancel` frees the task slot immediately (tail clears the slot only if it still holds the same task) + test "cancel then start → `.running` synchronously"; `RecognitionSection.onRetry` clears `router.highlightedModel`; `HotkeyRecorder` filters `willCloseNotification` to its own window; the download relay validates the HTTP status (200…299) before moving the file, else throws `URLError(.badServerResponse)` — tested with a `URLProtocol` stub on an injectable `sessionConfiguration`.
- [ ] Commit — `Tokenise on-accent white, seed the trimmer tests, align the spec with the finished tree`

---

# Batch D — Translation

### Task D0: Batch C review residuals

- [ ] README Tests section: the suite needs no microphone; one download test touches the network briefly. Spec §9: drop the per-stage install sentence (§10 holds the single-install policy). Delete the unused `TranscriptionHistoryStore.recent(_:)`. `SettingsStore(defaults: UserDefaults = .standard)`; tests and the screenshot harness use an ephemeral suite via `TestSupport.swift` (`TestDefaults.ephemeral()`), then regenerate the screenshots. Nest the `URLProtocol` stubs inside `ModelCatalogTests`. Harness: one `XCTContext.runActivity` per surface, failures collected. Commit — `Fix Batch C review residuals: honest README, single install policy, ephemeral defaults in tests`

### Task D1: Translate the remaining Russian comments and strings

**Files:** every file under `SayVoice/` and `Tests/` still containing Cyrillic (list with the guard below); `AppCoordinator.swift:~209` `.transcriptionFailed("Не услышал ничего")` → `"Didn't catch anything"`; `Transcription/TranscriptionEngine.initialPrompt` — **the Russian prompt sentence given to whisper stays Russian when the language is Russian**: it is model input, not UI. Make it language-aware: a Russian wrapper for `ru`, an English wrapper otherwise/for `auto` — and keep the existing behaviour tests green (`VocabularyTests`); day-1 docs under `docs/` written in Russian (spec/plan/notes from 2026-09-08): translate headings and body to English, keeping code and file names.

- [ ] Guard before: `grep -rln "[А-Яа-яЁё]" SayVoice Tests docs project.yml .gitignore Scripts` — record the list.
- [ ] Translate comments faithfully (same meaning, no new claims); keep identifiers; keep the two Russian whisper-prompt strings and the picker endonyms.
- [ ] Guard after: the same grep returns only `RecognitionSection.swift` (endonyms) and `TranscriptionEngine.swift` (the Russian prompt wrapper).
- [ ] Full suite, Release build. Commit — `Translate the remaining comments, strings and docs to English`

---

## Self-review

**Spec coverage:** §5.3 → A1 (steps, art panel 240, no permission skip, three offered models, hotkey step, finish starts normal flow); §5.4 → B1–B2 (320, header pill, search, 2-line rows, coarse time, hover copy, Clear… confirmed, Settings, EmptyState with hotkey name); §5.6 → B3 (static icons, About → Settings › System, no download item); §6 → A1 (`AppWindow` for onboarding), B3 (`Features/MenuBar`), C1 (`.xcodeproj` out, README), C3 (tree); §7 → A1 (fraction wrapper, old onboarding), B3 (blinking timer), C1 (committed project); §8 → D1; §9 → C2.

**Placeholder scan:** README/spec edits are described by section list and exact sentences; the screenshot harness reuses the Phase 1 renderer; every logic unit has code.

**Type consistency:** `OnboardingModel.step/next/skip/canSkip/canContinue/refreshPermissions/startPolling/stopPolling` used identically in A1's steps and tests; `HistoryPopover(entries:status:hotkeyName:onClear:onSettings:)` in B2 and B3; `StatusIcon.image(for:appearance:)` in B3 and its test; `EmptyState(symbol:title:hint:)` in B1 and B2; `RelativeTime.coarse(_:now:calendar:)` in B1 and B2; `HistoryFilter.apply(_:query:)` in B1 and B2.

**Batch boundaries:** A touches `Features/Onboarding`, `AppCoordinator` (onboarding block), `ModelManager`, `UI/OnboardingView.swift`. B touches `DesignSystem/EmptyState`, `Features/History`, `Features/MenuBar`, `AppCoordinator` (menu wiring), `UI/*`. C touches repo files, tests, tokens, spec. D touches comments everywhere — last, alone.
