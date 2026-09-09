# UI Redesign — Phase 2: Settings — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single long settings form with the spec's settings window — icon rail plus five sections built from the design system — including an in-place model download with progress and cancel, and remove the separate model-download window.

**Architecture:** Two new design-system components (`ModelRow`, `DownloadProgress`) take plain values only. `TagField` moves into the design system; the hotkey recorder moves to `Features/Settings/` because it depends on the `Hotkey` domain type. Feature logic lives in `Features/Settings/`: a `ModelDownloads` observable turns `ModelManager`'s byte stream into `DownloadState`s and owns cancellation; a `SettingsRouter` observable lets `AppCoordinator` open a given section and highlight a model. A small `AppStatus` observable exposes the app state to the settings header pill. `AppWindow.make` replaces the hand-written `NSWindow` block for settings (onboarding follows in Phase 3).

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI + AppKit, macOS 26, XcodeGen 2.46, XCTest. Phase 1 tokens and components are in the tree (`DS.*`, `Orb`, `Card`, `SettingsRow`, `Chip`, `KeyCap`, button styles).

**Spec:** `docs/superpowers/specs/2026-09-09-ui-redesign-design.md` — §4 (components), §5.1 (settings), §5.5 (model download), §6 (architecture). Phase 1 plan: `docs/superpowers/plans/2026-09-09-ui-redesign-phase-1-foundation-overlay.md` (merged into `redesign/phase-1`, head `ba40d8a` or later).

## Global Constraints

- Deployment target **macOS 26.0**; no `#available` branches.
- **All new and rewritten files are in English** — UI strings, comments, identifiers. Files only lightly edited (`SettingsStore.swift`, `ModelManager.swift`, `AppCoordinator.swift`, `MenuBarController.swift`) keep their existing comment language; every user-visible string added or touched is English.
- **No third-party libraries.**
- `SayVoice/DesignSystem/` imports only SwiftUI/AppKit/CoreText/CoreGraphics and never references `SettingsStore`, `ModelManager`, `Hotkey`, `AppCoordinator`, `OverlayModel` or any feature/app type — components take plain values and closures.
- Colours only through `DS.Colors.*` (no literals outside `Colors.swift`); fonts only through `DS.font(_:)`.
- **Three-places accent rule** (spec §3.1 as amended): accent only on the orb/logo, the active or interactive control (selected row, on-state toggle, focused field border, `.dsLink`/`.dsPrimary`), and the overlay glass. Section titles, icons, badges (except the "recommended" chip, which is an accent chip by spec §4), notes and dividers are neutral.
- Settings window **780 × 600**, not resizable; rail 64 wide; sections General · Recognition · Dictionary · Insertion · System; every section fits without scrolling except Recognition.
- Commit after every task; messages in English, imperative; **no AI-attribution lines**.
- Do not touch: `Audio/`, `Transcription/`, `TextInjection/`, `HotkeyListener/`, `Permissions/`, `History/`, `Packages/`, `Features/Overlay/`, `UI/OnboardingView.swift`, `UI/HistoryPopoverView.swift` (Phase 3).
- Generated project: run `xcodegen generate` after adding/moving/deleting files; commit the regenerated `SayVoice.xcodeproj` with the change.
- Build: `xcodebuild -project SayVoice.xcodeproj -scheme SayVoice -configuration Release -derivedDataPath build build 2>&1 | grep -E "error:|BUILD"`
- Test: `xcodebuild -project SayVoice.xcodeproj -scheme SayVoice -derivedDataPath build test 2>&1 | grep -E "error:|Test Case|Executed|FAILED|passed|failed" | tail -40`
- **No installs to /Applications and no launching the app in this phase** — the owner tests once everything is done.

---

## File structure

**Created**

| Path | Responsibility |
|---|---|
| `SayVoice/DesignSystem/Components/DownloadProgress.swift` | `DownloadState` enum + `DownloadProgress` view (idle/running/failed/done) + status text formatter |
| `SayVoice/DesignSystem/Components/ModelRow.swift` | Selectable model row: indicator, name, badge chip, 5-step quality bar, size chip, downloaded chip; hosts `DownloadProgress` |
| `SayVoice/DesignSystem/Components/TagField.swift` | Moved from `UI/`, restyled to tokens, English strings |
| `SayVoice/App/AppStatus.swift` | `@Observable` app state + model name for the settings header pill |
| `SayVoice/App/AppWindow.swift` | `AppWindow.make(title:size:content:)` — the one way windows are created |
| `SayVoice/Features/Settings/SettingsSection.swift` | The five sections: id, title, subtitle, SF symbol |
| `SayVoice/Features/Settings/SettingsRouter.swift` | `@Observable` current section + model to highlight |
| `SayVoice/Features/Settings/ModelDownloads.swift` | Feature logic: per-model `DownloadState`, start/cancel, speed and ETA, completion callback |
| `SayVoice/Features/Settings/HotkeyRecorder.swift` | Moved from `UI/HotkeyRecorderField.swift`, restyled, English |
| `SayVoice/Features/Settings/SettingsView.swift` | Window root: rail + section header + section content |
| `SayVoice/Features/Settings/SettingsRail.swift` | Icon rail with logo mark and five items |
| `SayVoice/Features/Settings/SectionHeader.swift` | Title, subtitle, status pill |
| `SayVoice/Features/Settings/GeneralSection.swift` | Hotkey card (recorder + mode), recording-behaviour card |
| `SayVoice/Features/Settings/RecognitionSection.swift` | Model card with `ModelRow`s + download, language card |
| `SayVoice/Features/Settings/DictionarySection.swift` | `TagField` card |
| `SayVoice/Features/Settings/InsertionSection.swift` | Method, restore-clipboard, dynamic notes |
| `SayVoice/Features/Settings/SystemSection.swift` | Launch at login, version, source link, licenses |
| `SayVoice/Features/Settings/LicensesSheet.swift` | Three licence texts read from the bundle |
| `SayVoice/Resources/Licenses/whisper.cpp-LICENSE.txt` | MIT text for the vendored whisper.cpp |
| `Tests/SayVoiceTests/ModelCatalogTests.swift`, `DownloadProgressTests.swift`, `SettingsRenderTests.swift` | See tasks |

**Modified**

| Path | Change |
|---|---|
| `SayVoice/ModelManagement/ModelManager.swift` | `ModelSize.qualitySteps`; `downloadModelProgress(_:)` byte stream with cancellation and temp cleanup; `downloadModel(_:)` becomes a fraction-mapping wrapper (removed in Phase 3) |
| `SayVoice/Settings/SettingsStore.swift` | Default `modelSize` → `"large-v3-turbo-q5"` |
| `SayVoice/App/AppCoordinator.swift` | `AppStatus`, `SettingsRouter`, `ModelDownloads` owned here; `showSettings(section:highlight:)` via `AppWindow`; model-missing paths open Recognition; `?? .small` fallbacks → `?? .turboQ5`; `showModelDownloadWindow` removed |
| `SayVoice/UI/MenuBarController.swift` | "Скачать модель…" item and `onDownloadModel` removed |
| `docs/superpowers/specs/2026-09-09-ui-redesign-design.md` | §4: `HotkeyRecorder` row notes it lives in `Features/Settings/` (depends on `Hotkey`); §3.4 auto-dismiss text updated; §5.1 default model note |

**Deleted**

| Path | Replaced by |
|---|---|
| `SayVoice/UI/SettingsView.swift` | `Features/Settings/*` |
| `SayVoice/UI/TagField.swift` | `DesignSystem/Components/TagField.swift` |
| `SayVoice/UI/HotkeyRecorderField.swift` | `Features/Settings/HotkeyRecorder.swift` |
| `SayVoice/ModelManagement/ModelDownloadView.swift` | `ModelRow` + `DownloadProgress` in Recognition |

`SayVoice/UI/` keeps `OnboardingView.swift`, `HistoryPopoverView.swift`, `MenuBarController.swift` until Phase 3. `OnboardingView` still calls `modelManager.downloadModel(.small)` — the wrapper keeps it compiling.

---

### Task 1: Model catalogue additions and a cancellable byte-level download

**Files:**
- Modify: `SayVoice/ModelManagement/ModelManager.swift`
- Modify: `SayVoice/Settings/SettingsStore.swift:138` (default model)
- Modify: `SayVoice/App/AppCoordinator.swift` (three `?? .small` fallbacks → `?? .turboQ5`)
- Test: `Tests/SayVoiceTests/ModelCatalogTests.swift`

**Interfaces:**
- Produces: `ModelManager.ModelSize.qualitySteps: Int` (1…5); `ModelManager.ModelSize.recommended: ModelSize` (`.turboQ5`); `struct ModelDownloadProgress: Sendable { bytesReceived: Int64; totalBytes: Int64; var fraction: Double }`; `ModelManager.downloadModelProgress(_:) -> AsyncThrowingStream<ModelDownloadProgress, Error>` that stops (and deletes its `.tmp`) when the consuming task is cancelled; `downloadModel(_:)` unchanged in signature.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import SayVoice

final class ModelCatalogTests: XCTestCase {

    func testEveryModelHasAQualityStepInRange() {
        for m in ModelManager.ModelSize.allCases {
            XCTAssertTrue((1...5).contains(m.qualitySteps), "\(m) has \(m.qualitySteps)")
        }
    }

    func testQualityIsMonotonicAcrossTheCatalogue() {
        let steps = ModelManager.ModelSize.allCases.map(\.qualitySteps)
        XCTAssertEqual(steps, steps.sorted(), "catalogue is listed from lightest to best")
    }

    func testRecommendedIsTurboQ5AndIsTheStoreDefault() {
        XCTAssertEqual(ModelManager.ModelSize.recommended, .turboQ5)
        XCTAssertEqual(ModelManager.ModelSize(settingsString: "large-v3-turbo-q5"), .turboQ5)
    }

    func testProgressFractionIsClampedAndSafe() {
        XCTAssertEqual(ModelDownloadProgress(bytesReceived: 50, totalBytes: 200).fraction, 0.25)
        XCTAssertEqual(ModelDownloadProgress(bytesReceived: 10, totalBytes: 0).fraction, 0, "unknown total → 0, never NaN")
        XCTAssertEqual(ModelDownloadProgress(bytesReceived: 300, totalBytes: 200).fraction, 1)
    }

    @MainActor
    func testDownloadStreamStopsWhenConsumerIsCancelled() async {
        // A cancelled consumer must see the stream end promptly — as nil
        // (AsyncThrowingStream ends on cancellation) or as an error — instead
        // of hanging on the connection until the transfer finishes.
        let manager = ModelManager()
        let task = Task { () -> String in
            var count = 0
            do {
                for try await _ in manager.downloadModelProgress(.base) { count += 1 }
                return "ended after \(count) chunk(s)"
            } catch {
                return "ended with \(type(of: error))"
            }
        }
        try? await Task.sleep(for: .milliseconds(150))
        let cancelledAt = Date()
        task.cancel()
        let result = await task.value
        let waited = Date().timeIntervalSince(cancelledAt)
        XCTAssertLessThan(waited, 3, "stream kept running \(waited)s after cancel (\(result))")
    }
}
```

The last test touches the network for ~150 ms; offline it ends with a URL error immediately — also a pass. The worker's `catch` removes the `.tmp` file after the consumer has already returned, so the test does not assert on the file.

- [ ] **Step 2: Run tests to verify they fail** — `cannot find 'ModelDownloadProgress'`, `has no member 'qualitySteps'`.

- [ ] **Step 3: Extend `ModelSize` in `ModelManager.swift`**

Inside `enum ModelSize`, after `settingsString`:

```swift
        /// The model preselected on first run and used as the fallback when the
        /// stored setting is unknown.
        static let recommended: ModelSize = .turboQ5

        /// Relative quality on a five-step scale, for the bar in ModelRow.
        /// Ordered with the catalogue: lighter models first.
        var qualitySteps: Int {
            switch self {
            case .base:    return 2
            case .small:   return 3
            case .turboQ5: return 4
            case .turboQ8: return 5
            case .turbo:   return 5
            }
        }
```

- [ ] **Step 4: Add the progress type and the cancellable stream**

Above `final class ModelManager`:

```swift
/// Progress of one model download, in bytes so consumers can compute speed
/// and time remaining themselves.
struct ModelDownloadProgress: Sendable, Equatable {
    let bytesReceived: Int64
    let totalBytes: Int64

    /// 0…1; 0 while the total is unknown.
    var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(bytesReceived) / Double(totalBytes))
    }
}
```

Replace the existing `downloadModel(_:)` with:

```swift
    /// Streams byte-level progress. Cancelling the consuming task stops the
    /// transfer and removes the partial file; the stream then ends with
    /// `CancellationError`.
    func downloadModelProgress(_ size: ModelSize) -> AsyncThrowingStream<ModelDownloadProgress, Error> {
        let directory = Self.modelsDirectory
        let fileName = size.fileName
        let url = size.downloadURL

        return AsyncThrowingStream { continuation in
            let worker = Task.detached {
                let tempURL = directory.appendingPathComponent(fileName + ".tmp")
                let finalURL = directory.appendingPathComponent(fileName)
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

                    let (bytes, response) = try await URLSession.shared.bytes(from: url)
                    let totalBytes = response.expectedContentLength

                    if FileManager.default.fileExists(atPath: tempURL.path) {
                        try FileManager.default.removeItem(at: tempURL)
                    }
                    FileManager.default.createFile(atPath: tempURL.path, contents: nil)
                    let handle = try FileHandle(forWritingTo: tempURL)
                    defer { try? handle.close() }

                    var received: Int64 = 0
                    var chunk = Data()
                    chunk.reserveCapacity(65_536)

                    for try await byte in bytes {
                        // URLSession.AsyncBytes throws CancellationError here once the
                        // task is cancelled, which is what ends the stream promptly.
                        chunk.append(byte)
                        received += 1
                        if chunk.count >= 65_536 {
                            try handle.write(contentsOf: chunk)
                            chunk.removeAll(keepingCapacity: true)
                            continuation.yield(ModelDownloadProgress(bytesReceived: received, totalBytes: totalBytes))
                        }
                    }
                    if !chunk.isEmpty { try handle.write(contentsOf: chunk) }

                    if FileManager.default.fileExists(atPath: finalURL.path) {
                        try FileManager.default.removeItem(at: finalURL)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: finalURL)
                    continuation.yield(ModelDownloadProgress(bytesReceived: received, totalBytes: max(totalBytes, received)))
                    continuation.finish()
                    print("[SayVoice] Model downloaded: \(finalURL.path)")
                } catch {
                    try? FileManager.default.removeItem(at: tempURL)
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }

    /// Fraction-only view of `downloadModelProgress`, kept for the onboarding
    /// step until Phase 3 replaces it.
    func downloadModel(_ size: ModelSize) -> AsyncThrowingStream<Double, Error> {
        let source = downloadModelProgress(size)
        return AsyncThrowingStream { continuation in
            let relay = Task {
                do {
                    for try await p in source { continuation.yield(p.fraction) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in relay.cancel() }
        }
    }
```

- [ ] **Step 5: Default model**

`SayVoice/Settings/SettingsStore.swift`, in `init`: `self.modelSize = d.string(forKey: SettingsKeys.modelSize) ?? "small"` → `?? ModelManager.ModelSize.recommended.settingsString`.
`SayVoice/App/AppCoordinator.swift`: the three occurrences of `ModelManager.ModelSize(settingsString: settingsStore.modelSize) ?? .small` → `?? .recommended`.

- [ ] **Step 6: Build, test — expect PASS** (`Executed 40 tests`).

- [ ] **Step 7: Commit**

```bash
git add SayVoice/ModelManagement/ModelManager.swift SayVoice/Settings/SettingsStore.swift SayVoice/App/AppCoordinator.swift Tests/SayVoiceTests/ModelCatalogTests.swift SayVoice.xcodeproj
git commit -m "Add a cancellable byte-level model download; make Large Turbo Q5 the default

Progress is reported in bytes so the UI can show speed and time left.
Cancelling the consumer stops the transfer and removes the partial file.
The fraction-only stream stays as a wrapper for the onboarding step
until Phase 3 replaces it."
```

---

### Task 2: `DownloadProgress` component

**Files:**
- Create: `SayVoice/DesignSystem/Components/DownloadProgress.swift`
- Test: `Tests/SayVoiceTests/DownloadProgressTests.swift`; append render tests to `Tests/SayVoiceTests/ComponentRenderTests.swift`

**Interfaces:**
- Produces: `enum DownloadState: Equatable { idle; running(fraction: Double, bytesPerSecond: Double?, secondsLeft: Double?); failed(String); done }`; `struct DownloadProgress: View { init(state: DownloadState, onStart: () -> Void, onCancel: () -> Void, onRetry: () -> Void) }`; `DownloadProgress.statusText(fraction:bytesPerSecond:secondsLeft:) -> String`.

- [ ] **Step 1: Write the failing tests**

`DownloadProgressTests.swift`:

```swift
import XCTest
@testable import SayVoice

final class DownloadProgressTests: XCTestCase {

    func testStatusTextWithSpeedAndEta() {
        XCTAssertEqual(DownloadProgress.statusText(fraction: 0.34, bytesPerSecond: 12_400_000, secondsLeft: 38), "34% · 12.4 MB/s · 38 s left")
    }

    func testStatusTextWithoutSpeedYet() {
        XCTAssertEqual(DownloadProgress.statusText(fraction: 0.02, bytesPerSecond: nil, secondsLeft: nil), "2%")
    }

    func testStatusTextMinutesAndHours() {
        XCTAssertEqual(DownloadProgress.statusText(fraction: 0.5, bytesPerSecond: 900_000, secondsLeft: 125), "50% · 0.9 MB/s · 2 min left")
        XCTAssertEqual(DownloadProgress.statusText(fraction: 0.1, bytesPerSecond: 100_000, secondsLeft: 4_000), "10% · 0.1 MB/s · 1 h 7 min left")
    }

    func testStatusTextClampsFraction() {
        XCTAssertEqual(DownloadProgress.statusText(fraction: 1.4, bytesPerSecond: nil, secondsLeft: nil), "100%")
        XCTAssertEqual(DownloadProgress.statusText(fraction: -1, bytesPerSecond: nil, secondsLeft: nil), "0%")
    }
}
```

Append to `ComponentRenderTests`:

```swift
    func testDownloadProgressRendersEveryState() {
        let states: [DownloadState] = [.idle, .running(fraction: 0.34, bytesPerSecond: 12_400_000, secondsLeft: 38), .failed("The network connection was lost."), .done]
        for state in states {
            for dark in [true, false] {
                let s = renderSize(DownloadProgress(state: state, onStart: {}, onCancel: {}, onRetry: {}), width: 480, dark: dark)
                XCTAssertEqual(s.width, 480, accuracy: 0.5)
                XCTAssertGreaterThan(s.height, 20)
            }
        }
    }
```

- [ ] **Step 2: Run to verify failure** — `cannot find 'DownloadProgress'`.

- [ ] **Step 3: Create `DownloadProgress.swift`**

```swift
import SwiftUI

/// Download lifecycle as seen by the UI. Feature code maps its transfer
/// stream onto these values; the component only renders them.
enum DownloadState: Equatable {
    case idle
    case running(fraction: Double, bytesPerSecond: Double?, secondsLeft: Double?)
    case failed(String)
    case done
}

/// One download control: a Download button, then a progress bar with
/// speed and time left and a Cancel link, then Retry on failure, then a
/// "Downloaded" chip. Used by the settings model list and by onboarding.
struct DownloadProgress: View {
    let state: DownloadState
    let onStart: () -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void

    init(state: DownloadState, onStart: @escaping () -> Void, onCancel: @escaping () -> Void, onRetry: @escaping () -> Void) {
        self.state = state
        self.onStart = onStart
        self.onCancel = onCancel
        self.onRetry = onRetry
    }

    var body: some View {
        switch state {
        case .idle:
            HStack {
                Spacer(minLength: 0)
                Button("Download", action: onStart).buttonStyle(.dsPrimary)
            }

        case let .running(fraction, speed, eta):
            VStack(alignment: .leading, spacing: DS.Space.s8) {
                ProgressView(value: min(1, max(0, fraction)))
                    .progressViewStyle(.linear)
                    .tint(DS.Colors.accent.color)
                HStack {
                    Text(Self.statusText(fraction: fraction, bytesPerSecond: speed, secondsLeft: eta))
                        .font(DS.font(.valueSmall))
                        .foregroundStyle(DS.Colors.muted.color)
                    Spacer(minLength: DS.Space.s8)
                    Button("Cancel", action: onCancel).buttonStyle(.dsLink)
                }
            }

        case let .failed(message):
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s12) {
                Text(message)
                    .font(DS.font(.caption))
                    .foregroundStyle(DS.Colors.warn.color)
                    .lineLimit(2)
                Spacer(minLength: DS.Space.s8)
                Button("Retry", action: onRetry).buttonStyle(.dsSecondary)
            }

        case .done:
            HStack {
                Spacer(minLength: 0)
                Chip("downloaded", style: .ok)
            }
        }
    }

    /// "34% · 12.4 MB/s · 38 s left" — parts are omitted while unknown.
    static func statusText(fraction: Double, bytesPerSecond: Double?, secondsLeft: Double?) -> String {
        let percent = Int((min(1, max(0, fraction)) * 100).rounded(.down))
        var parts = ["\(percent)%"]
        if let bytesPerSecond, bytesPerSecond > 0 {
            parts.append(String(format: "%.1f MB/s", bytesPerSecond / 1_000_000))
        }
        if let secondsLeft, secondsLeft.isFinite, secondsLeft >= 0 {
            parts.append(Self.etaText(secondsLeft))
        }
        return parts.joined(separator: " · ")
    }

    private static func etaText(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s) s left" }
        let minutes = s / 60
        if minutes < 60 { return "\(minutes) min left" }
        return "\(minutes / 60) h \(minutes % 60) min left"
    }
}
```

- [ ] **Step 4: Run tests — expect PASS** (`Executed 45 tests`).

- [ ] **Step 5: Commit**

```bash
git add SayVoice/DesignSystem/Components/DownloadProgress.swift Tests/SayVoiceTests SayVoice.xcodeproj
git commit -m "Add DownloadProgress component with speed and time-left formatting"
```

---

### Task 3: `ModelRow` component

**Files:**
- Create: `SayVoice/DesignSystem/Components/ModelRow.swift`
- Test: append to `Tests/SayVoiceTests/ComponentRenderTests.swift`

**Interfaces:**
- Produces:
```swift
struct ModelRow: View {
    init(name: String, badge: String? = nil, badgeIsAccent: Bool = false, qualitySteps: Int, sizeText: String,
         isSelected: Bool, isDownloaded: Bool, isHighlighted: Bool = false, download: DownloadState?,
         onSelect: @escaping () -> Void, onDownload: @escaping () -> Void, onCancel: @escaping () -> Void, onRetry: @escaping () -> Void)
}
```

- [ ] **Step 1: Write the failing test**

```swift
    func testModelRowRendersSelectedDownloadedAndDownloading() {
        let variants: [(Bool, Bool, DownloadState?)] = [
            (true, true, nil),
            (false, false, .idle),
            (false, false, .running(fraction: 0.6, bytesPerSecond: 8_000_000, secondsLeft: 20)),
            (false, false, .failed("Timed out")),
        ]
        for (selected, downloaded, download) in variants {
            for dark in [true, false] {
                let s = renderSize(
                    ModelRow(name: "Large Turbo Q5", badge: "recommended", badgeIsAccent: true, qualitySteps: 4, sizeText: "574 MB",
                             isSelected: selected, isDownloaded: downloaded, download: download,
                             onSelect: {}, onDownload: {}, onCancel: {}, onRetry: {}),
                    width: 640, dark: dark)
                XCTAssertEqual(s.width, 640, accuracy: 0.5)
                XCTAssertGreaterThan(s.height, download == nil ? 36 : 60)
            }
        }
    }
```

- [ ] **Step 2: Run to verify failure** — `cannot find 'ModelRow'`.

- [ ] **Step 3: Create `ModelRow.swift`**

```swift
import SwiftUI

/// One selectable model in the recognition list. Takes plain values: the
/// feature view maps the model catalogue onto them.
///
/// Row: selection indicator · name · badge · quality bar · downloaded · size.
/// A second line hosts `DownloadProgress` when a download is offered or
/// running. Selection tint is the accent (the "active control" place).
struct ModelRow: View {
    let name: String
    let badge: String?
    let badgeIsAccent: Bool
    let qualitySteps: Int
    let sizeText: String
    let isSelected: Bool
    let isDownloaded: Bool
    let isHighlighted: Bool
    let download: DownloadState?
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void

    init(
        name: String, badge: String? = nil, badgeIsAccent: Bool = false, qualitySteps: Int, sizeText: String,
        isSelected: Bool, isDownloaded: Bool, isHighlighted: Bool = false, download: DownloadState?,
        onSelect: @escaping () -> Void, onDownload: @escaping () -> Void,
        onCancel: @escaping () -> Void, onRetry: @escaping () -> Void
    ) {
        self.name = name; self.badge = badge; self.badgeIsAccent = badgeIsAccent
        self.qualitySteps = qualitySteps; self.sizeText = sizeText
        self.isSelected = isSelected; self.isDownloaded = isDownloaded; self.isHighlighted = isHighlighted
        self.download = download
        self.onSelect = onSelect; self.onDownload = onDownload; self.onCancel = onCancel; self.onRetry = onRetry
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s8) {
            Button(action: onSelect) {
                HStack(spacing: DS.Space.s12) {
                    indicator
                    Text(name)
                        .font(DS.font(isSelected ? .bodyMedium : .body))
                        .foregroundStyle(DS.Colors.text.color)
                    if let badge {
                        Chip(badge, style: badgeIsAccent ? .accent : .neutral)
                    }
                    qualityBar
                    Spacer(minLength: DS.Space.s12)
                    if isDownloaded {
                        Chip("downloaded", style: .ok)
                    }
                    Chip(sizeText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let download, !isDownloaded {
                DownloadProgress(state: download, onStart: onDownload, onCancel: onCancel, onRetry: onRetry)
                    .padding(.leading, 28)   // aligns with the name, past the indicator
            }
        }
        .padding(.horizontal, DS.Space.s12)
        .padding(.vertical, DS.Space.s8)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                .fill(isSelected ? DS.Colors.accentSoft.color : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                .strokeBorder(isSelected ? DS.Colors.accent.color : (isHighlighted ? DS.Colors.warn.color : DS.Colors.line.color), lineWidth: 1)
        )
        .animation(DS.Motion.stateChange, value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var indicator: some View {
        ZStack {
            Circle().strokeBorder(isSelected ? DS.Colors.accent.color : DS.Colors.faint.color, lineWidth: 1.5)
            if isSelected {
                Circle().fill(DS.Colors.accent.color).padding(4)
            }
        }
        .frame(width: 16, height: 16)
    }

    /// Five segments; filled ones show relative quality.
    private var qualityBar: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(i < qualitySteps ? DS.Colors.muted.color : DS.Colors.line.color)
                    .frame(width: 14, height: 4)
            }
        }
        .accessibilityLabel("Quality \(qualitySteps) of 5")
    }
}
```

- [ ] **Step 4: Run tests — expect PASS** (`Executed 46 tests`).

- [ ] **Step 5: Commit**

```bash
git add SayVoice/DesignSystem/Components/ModelRow.swift Tests/SayVoiceTests/ComponentRenderTests.swift SayVoice.xcodeproj
git commit -m "Add ModelRow component with quality bar and inline download"
```

---

### Task 4: Move and restyle `TagField` (design system) and the hotkey recorder (settings feature)

**Files:**
- Move: `SayVoice/UI/TagField.swift` → `SayVoice/DesignSystem/Components/TagField.swift`
- Move: `SayVoice/UI/HotkeyRecorderField.swift` → `SayVoice/Features/Settings/HotkeyRecorder.swift`
- Modify: `SayVoice/UI/SettingsView.swift` (two call sites, so the old view keeps compiling until Task 8 deletes it)
- Modify: `docs/superpowers/specs/2026-09-09-ui-redesign-design.md` §4 (`HotkeyRecorder` row)
- Test: `Tests/SayVoiceTests/VocabularyTests.swift` (unchanged, must still pass); append to `ComponentRenderTests`

**Interfaces:**
- Produces: `TagField(text: Binding<String>, placeholder: String)` unchanged API, tokens only, English; `TagField.tokens(from:)` / `string(from:)` unchanged. `HotkeyRecorder(hotkey: Binding<Hotkey>, onChange: ((Hotkey) -> Void)?)` — the old label "Хоткей записи" is gone (the enclosing `SettingsRow` provides it).

- [ ] **Step 1: Add the failing render test**

```swift
    func testTagFieldRendersWithChips() {
        let s = renderSize(TagField(text: .constant("API, deployment, SwiftUI"), placeholder: "Add term"), width: 480)
        XCTAssertEqual(s.width, 480, accuracy: 0.5)
        XCTAssertGreaterThan(s.height, 30)
    }
```

- [ ] **Step 2: Move `TagField`**

```bash
git mv SayVoice/UI/TagField.swift SayVoice/DesignSystem/Components/TagField.swift
```

Then rewrite the file's *presentation* while keeping its logic. Replace the whole file with:

```swift
import AppKit
import SwiftUI

/// Row height shared by chips, the input and the placeholder so the line
/// reads as one, and the caret sits level with the chips.
private let tagRowHeight: CGFloat = 26

/// Term editor rendered as chips.
///
/// Stores and exposes a comma-separated string — the same format the app has
/// always kept in settings — so no migration is needed and the transcription
/// prompt receives what it always did. Enter or comma adds a term, Backspace
/// in an empty input removes the last one, duplicates (case-insensitive) are
/// ignored.
struct TagField: View {
    @Binding var text: String
    var placeholder: String = ""

    @State private var draft: String = ""
    @FocusState private var isFocused: Bool

    private var tags: [String] { Self.tokens(from: text) }

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 6, minTrailingWidth: 60) {
            ForEach(tags, id: \.self) { tag in
                TagChip(title: tag) { remove(tag) }
            }

            // Inside a grouped Form, SwiftUI treats a TextField as a
            // "label + control" row and repositions the editor itself;
            // labelsHidden keeps the editor where the layout puts it.
            TextField(placeholder, text: $draft)
                .labelsHidden()
                .textFieldStyle(.plain)
                .font(DS.font(.body))
                .foregroundStyle(DS.Colors.text.color)
                .frame(height: tagRowHeight)
                .focused($isFocused)
                .onSubmit(commitDraft)
                .onChange(of: draft) { _, new in
                    guard new.contains(",") else { return }
                    let parts = new.split(separator: ",", omittingEmptySubsequences: false)
                    for part in parts.dropLast() { append(String(part)) }
                    draft = String(parts.last ?? "")
                }
                .onKeyPress(.delete) {
                    guard draft.isEmpty, !tags.isEmpty else { return .ignored }
                    remove(tags[tags.count - 1])
                    return .handled
                }
        }
        .padding(DS.Space.s8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous).fill(DS.Colors.surface2.color))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                .strokeBorder(isFocused ? DS.Colors.accent.color : DS.Colors.line.color, lineWidth: 1)
        )
        .animation(DS.Motion.stateChange, value: isFocused)
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
    }

    // MARK: - Editing

    private func commitDraft() {
        append(draft)
        draft = ""
    }

    private func append(_ raw: String) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        guard !tags.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else { return }
        text = Self.string(from: tags + [value])
    }

    private func remove(_ tag: String) {
        text = Self.string(from: tags.filter { $0 != tag })
    }

    // MARK: - Settings string <-> terms

    /// Splits the stored string into terms on commas and newlines.
    static func tokens(from string: String) -> [String] {
        string
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Joins terms back into the stored string.
    static func string(from tokens: [String]) -> String {
        tokens
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

// MARK: - Chip

private struct TagChip: View {
    let title: String
    let onRemove: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(DS.font(.bodyMedium))
                .foregroundStyle(DS.Colors.text.color)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isHovering ? DS.Colors.text.color : DS.Colors.muted.color)
            }
            .buttonStyle(.plain)
            .help("Remove “\(title)”")
        }
        .padding(.leading, 9)
        .padding(.trailing, 7)
        .frame(height: tagRowHeight)
        .background(Capsule().fill(DS.Colors.surface.color.opacity(isHovering ? 1 : 0.85)))
        .overlay(Capsule().strokeBorder(DS.Colors.line.color, lineWidth: 1))
        .onHover { isHovering = $0 }
        .animation(DS.Motion.stateChange, value: isHovering)
    }
}

// MARK: - Flow layout

/// Wraps items onto new lines; the last item (the input) takes the rest of
/// its line or moves to a new one if less than `minTrailingWidth` is left.
/// Measurement and placement share one function so they cannot disagree.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6
    var minTrailingWidth: CGFloat = 60

    private func arrange(maxWidth: CGFloat, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        let width = maxWidth.isFinite ? maxWidth : .greatestFiniteMagnitude
        var frames: [CGRect] = []
        var lineOfFrame: [Int] = []
        var lineTops: [CGFloat] = [0]
        var lineHeights: [CGFloat] = [0]
        var x: CGFloat = 0, y: CGFloat = 0, line = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0

        func breakLine() {
            lineHeights[line] = lineHeight
            y += lineHeight + lineSpacing
            line += 1
            lineTops.append(y)
            lineHeights.append(0)
            x = 0
            lineHeight = 0
        }

        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            if index == subviews.count - 1 {
                var remaining = width - x
                if x > 0 && remaining < minTrailingWidth {
                    breakLine()
                    remaining = width
                }
                size.width = max(minTrailingWidth, remaining)
            } else if x > 0 && x + size.width > width {
                breakLine()
            }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            lineOfFrame.append(line)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            lineHeights[line] = lineHeight
            widest = max(widest, x - spacing)
        }
        for index in frames.indices {
            let l = lineOfFrame[index]
            frames[index].origin.y = lineTops[l] + (lineHeights[l] - frames[index].height) / 2
        }
        return (frames, CGSize(width: min(width, widest), height: y + lineHeight))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(maxWidth: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(maxWidth: bounds.width, subviews: subviews).frames
        for index in subviews.indices {
            let f = frames[index]
            subviews[index].place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY),
                                  proposal: ProposedViewSize(width: f.width, height: f.height))
        }
    }
}
```

- [ ] **Step 3: Move the hotkey recorder**

```bash
git mv SayVoice/UI/HotkeyRecorderField.swift SayVoice/Features/Settings/HotkeyRecorder.swift
```

Replace the file with (logic unchanged, presentation on tokens, English, no label row):

```swift
import AppKit
import SwiftUI

/// Hotkey assignment field: click, press a key or a mouse button, done.
///
/// Uses a local `NSEvent` monitor, which works while the settings window is
/// active and needs neither an event tap nor accessibility rights. A lone
/// modifier counts on *release*, otherwise holding ⌥ on the way to ⌥⌘D would
/// register as "⌥".
struct HotkeyRecorder: View {
    @Binding var hotkey: Hotkey
    /// Called with the new hotkey so the coordinator applies it live.
    var onChange: ((Hotkey) -> Void)?

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var rejection: String?
    @State private var pendingModifier: CGKeyCode?
    @State private var sawKeyDown = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: DS.Space.s8) {
                if hotkey != .default && !isRecording {
                    Button("Reset") { save(.default) }.buttonStyle(.dsLink)
                }
                Button(action: toggleRecording) {
                    Text(isRecording ? "Press a key or mouse button…" : hotkey.displayName)
                        .font(DS.font(.value))
                        .foregroundStyle(isRecording ? DS.Colors.accent.color : DS.Colors.text.color)
                        .frame(minWidth: 150)
                        .padding(.vertical, 6)
                        .padding(.horizontal, DS.Space.s12)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous).fill(DS.Colors.surface2.color))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                                .strokeBorder(isRecording ? DS.Colors.accent.color : DS.Colors.line.color, lineWidth: isRecording ? 1.5 : 1)
                        )
                }
                .buttonStyle(.plain)
                .help(isRecording ? "Esc cancels" : "Click to assign another key or mouse button")
            }

            if let rejection {
                Label(rejection, systemImage: "exclamationmark.triangle.fill")
                    .font(DS.font(.caption)).foregroundStyle(DS.Colors.warn.color)
                    .multilineTextAlignment(.trailing)
            } else if let warning = hotkey.warning {
                Label(warning, systemImage: "info.circle")
                    .font(DS.font(.caption)).foregroundStyle(DS.Colors.muted.color)
                    .multilineTextAlignment(.trailing)
            }
        }
        .onDisappear(perform: stopRecording)
    }

    // MARK: - Recording

    private func toggleRecording() { isRecording ? stopRecording() : startRecording() }

    private func startRecording() {
        rejection = nil
        pendingModifier = nil
        sawKeyDown = false
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .otherMouseDown]) { event in
            handle(event)
            return nil   // swallowed while recording
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        pendingModifier = nil
        sawKeyDown = false
    }

    private func handle(_ event: NSEvent) {
        let code = CGKeyCode(event.keyCode)
        let cgFlags = Self.cgFlags(from: event.modifierFlags)

        switch event.type {
        case .otherMouseDown:
            let button = event.buttonNumber
            if let rejected = Hotkey.validate(mouseButton: button) {
                rejection = rejected.message
                return
            }
            save(Hotkey(mouseButton: button))

        case .keyDown:
            sawKeyDown = true
            pendingModifier = nil
            if code == 53, cgFlags == 0 {   // Esc without modifiers cancels
                stopRecording()
                return
            }
            accept(keyCode: code, flags: cgFlags)

        case .flagsChanged:
            guard let modifier = Hotkey.modifierKeys[code] else { return }
            let isPressed = cgFlags & modifier.mask.rawValue != 0
            if isPressed {
                pendingModifier = code
                sawKeyDown = false
            } else if pendingModifier == code, !sawKeyDown {
                accept(keyCode: code, flags: modifier.mask.rawValue)
            }

        default:
            break
        }
    }

    private func accept(keyCode code: CGKeyCode, flags newFlags: UInt64) {
        if let rejected = Hotkey.validate(keyCode: code, flags: newFlags) {
            rejection = rejected.message
            return
        }
        save(Hotkey(keyCode: code, flags: newFlags))
    }

    private func save(_ new: Hotkey) {
        hotkey = new
        rejection = nil
        stopRecording()
        onChange?(new)
    }

    /// NSEvent flags → the CGEvent masks the listener compares against.
    private static func cgFlags(from flags: NSEvent.ModifierFlags) -> UInt64 {
        var result: CGEventFlags = []
        if flags.contains(.command)  { result.insert(.maskCommand) }
        if flags.contains(.option)   { result.insert(.maskAlternate) }
        if flags.contains(.control)  { result.insert(.maskControl) }
        if flags.contains(.shift)    { result.insert(.maskShift) }
        if flags.contains(.function) { result.insert(.maskSecondaryFn) }
        return result.rawValue
    }
}
```

- [ ] **Step 4: Keep the old settings view compiling**

In `SayVoice/UI/SettingsView.swift` replace `HotkeyRecorderField(hotkey: $settings.hotkey, onChange: onHotkeyChanged)` with `HotkeyRecorder(hotkey: $settings.hotkey, onChange: onHotkeyChanged)`. `TagField(...)` call is unchanged.

- [ ] **Step 5: Spec note**

In spec §4 table, the `HotkeyRecorder` row's Purpose cell becomes: `Existing recorder, restyled; lives in Features/Settings/ because it depends on the Hotkey domain type`.

- [ ] **Step 6: Generate, build, test — expect PASS** (`Executed 47 tests`; `VocabularyTests` still green).

- [ ] **Step 7: Commit**

```bash
git add -A SayVoice/UI SayVoice/DesignSystem SayVoice/Features/Settings docs/superpowers/specs Tests/SayVoiceTests/ComponentRenderTests.swift SayVoice.xcodeproj
git commit -m "Move TagField into the design system and the hotkey recorder into Settings; restyle both on tokens"
```

---

### Task 5: `AppStatus`, `SettingsRouter`, `ModelDownloads`, `AppWindow`

**Files:**
- Create: `SayVoice/App/AppStatus.swift`, `SayVoice/App/AppWindow.swift`, `SayVoice/Features/Settings/SettingsSection.swift`, `SayVoice/Features/Settings/SettingsRouter.swift`, `SayVoice/Features/Settings/ModelDownloads.swift`
- Test: `Tests/SayVoiceTests/SettingsLogicTests.swift`

**Interfaces:**
- Produces:
  - `@MainActor @Observable final class AppStatus { var state: AppState; var modelName: String; var pillText: String }` — `pillText` is "Ready · Large Turbo Q5" / "Recording" / "Transcribing…" / "Inserting…" / "Needs attention".
  - `enum AppWindow { @MainActor static func make(title: String, size: NSSize, resizable: Bool = false, content: some View) -> NSWindow }`.
  - `enum SettingsSection: String, CaseIterable, Identifiable { general, recognition, dictionary, insertion, system; title; subtitle; symbol }`.
  - `@MainActor @Observable final class SettingsRouter { var section: SettingsSection; var highlightedModel: ModelManager.ModelSize? }`.
  - `@MainActor @Observable final class ModelDownloads { init(modelManager:); func state(for:) -> DownloadState?; func start(_:); func cancel(_:); var onCompleted: ((ModelManager.ModelSize) -> Void)? }` — `state(for:)` is `nil` when the model is on disk, `.idle` otherwise.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import SayVoice

@MainActor
final class SettingsLogicTests: XCTestCase {

    func testStatusPillText() {
        let s = AppStatus()
        s.modelName = "Large Turbo Q5"
        s.state = .idle;          XCTAssertEqual(s.pillText, "Ready · Large Turbo Q5")
        s.state = .recording;     XCTAssertEqual(s.pillText, "Recording")
        s.state = .transcribing;  XCTAssertEqual(s.pillText, "Transcribing…")
        s.state = .injecting;     XCTAssertEqual(s.pillText, "Inserting…")
        s.state = .error(.modelNotLoaded); XCTAssertEqual(s.pillText, "Needs attention")
    }

    func testSectionsAreOrderedAsSpecified() {
        XCTAssertEqual(SettingsSection.allCases.map(\.rawValue), ["general", "recognition", "dictionary", "insertion", "system"])
        for s in SettingsSection.allCases {
            XCTAssertFalse(s.title.isEmpty); XCTAssertFalse(s.subtitle.isEmpty); XCTAssertFalse(s.symbol.isEmpty)
        }
    }

    func testDownloadsReportNilForModelsOnDiskAndIdleOtherwise() {
        let downloads = ModelDownloads(modelManager: ModelManager())
        for m in ModelManager.ModelSize.allCases {
            let onDisk = ModelManager().isModelAvailable(m)
            XCTAssertEqual(downloads.state(for: m) == nil, onDisk, "\(m)")
        }
    }

    func testSpeedAndEtaFromTwoSamples() {
        let (speed, eta) = ModelDownloads.rate(previous: (bytes: 1_000_000, at: 10.0), current: (bytes: 3_000_000, at: 11.0), total: 13_000_000)
        XCTAssertEqual(speed!, 2_000_000, accuracy: 1)
        XCTAssertEqual(eta!, 5, accuracy: 0.01)
        let (s2, e2) = ModelDownloads.rate(previous: nil, current: (bytes: 10, at: 1), total: 100)
        XCTAssertNil(s2); XCTAssertNil(e2)
    }

    func testAppWindowIsFixedSizeAndTitled() {
        let w = AppWindow.make(title: "Test", size: NSSize(width: 300, height: 200), content: Text("x"))
        XCTAssertEqual(w.title, "Test")
        XCTAssertEqual(w.contentView?.frame.size, NSSize(width: 300, height: 200))
        XCTAssertFalse(w.styleMask.contains(.resizable))
        XCTAssertFalse(w.isReleasedWhenClosed)
        w.close()
    }
}
```

- [ ] **Step 2: Run to verify failure** — `cannot find 'AppStatus'`, etc.

- [ ] **Step 3: Create `AppStatus.swift`**

```swift
import Foundation

/// Read-only view of the app's state for UI that is not the coordinator —
/// the settings header pill today, the popover header in Phase 3.
@MainActor @Observable
final class AppStatus {
    var state: AppState = .idle
    /// Display name of the selected model, e.g. "Large Turbo Q5".
    var modelName: String = ""

    var pillText: String {
        switch state {
        case .idle:         return modelName.isEmpty ? "Ready" : "Ready · \(modelName)"
        case .recording:    return "Recording"
        case .transcribing: return "Transcribing…"
        case .injecting:    return "Inserting…"
        case .error:        return "Needs attention"
        }
    }

    var orbState: Orb.State {
        switch state {
        case .idle:         return .idle
        case .recording:    return .recording
        case .transcribing: return .transcribing
        case .injecting:    return .done
        case .error:        return .error
        }
    }
}
```

- [ ] **Step 4: Create `AppWindow.swift`**

```swift
import AppKit
import SwiftUI

/// The one way the app creates a standard window. Fixed size unless asked,
/// centred, kept alive after close so it can be shown again.
enum AppWindow {
    @MainActor
    static func make(title: String, size: NSSize, resizable: Bool = false, content: some View) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { style.insert(.resizable) }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.title = title
        window.contentView = NSHostingView(rootView: content)
        window.contentView?.frame = NSRect(origin: .zero, size: size)
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    /// Brings a window to the front and activates the app — menu-bar apps are
    /// not active when a window is requested from the status item.
    @MainActor
    static func present(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 5: Create `SettingsSection.swift` and `SettingsRouter.swift`**

```swift
import Foundation

/// The five settings sections, in rail order.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general, recognition, dictionary, insertion, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:     return "General"
        case .recognition: return "Recognition"
        case .dictionary:  return "Dictionary"
        case .insertion:   return "Insertion"
        case .system:      return "System"
        }
    }

    var subtitle: String {
        switch self {
        case .general:     return "Hotkey, overlay and recording behaviour"
        case .recognition: return "Model and language — everything runs offline"
        case .dictionary:  return "Terms the model should spell correctly"
        case .insertion:   return "How text reaches the active app"
        case .system:      return "Startup, version and licenses"
        }
    }

    /// SF Symbol for the rail.
    var symbol: String {
        switch self {
        case .general:     return "slider.horizontal.3"
        case .recognition: return "waveform"
        case .dictionary:  return "character.book.closed"
        case .insertion:   return "text.insert"
        case .system:      return "gearshape"
        }
    }
}
```

```swift
import Foundation

/// Where the settings window is, and what to draw attention to. Owned by the
/// coordinator so "open Recognition and highlight this model" is one call.
@MainActor @Observable
final class SettingsRouter {
    var section: SettingsSection = .general
    var highlightedModel: ModelManager.ModelSize?
}
```

- [ ] **Step 6: Create `ModelDownloads.swift`**

```swift
import Foundation

/// Turns `ModelManager`'s byte stream into `DownloadState`s the UI renders,
/// one per model, and owns the running tasks so Cancel actually cancels.
@MainActor @Observable
final class ModelDownloads {
    private let modelManager: ModelManager
    private var states: [ModelManager.ModelSize: DownloadState] = [:]
    private var tasks: [ModelManager.ModelSize: Task<Void, Never>] = [:]

    /// Called when a download finishes successfully.
    var onCompleted: ((ModelManager.ModelSize) -> Void)?

    init(modelManager: ModelManager) {
        self.modelManager = modelManager
    }

    /// `nil` when the model is already on disk (nothing to offer),
    /// `.idle` when it can be downloaded, otherwise the live state.
    func state(for size: ModelManager.ModelSize) -> DownloadState? {
        if modelManager.isModelAvailable(size) { return nil }
        return states[size] ?? .idle
    }

    func start(_ size: ModelManager.ModelSize) {
        guard tasks[size] == nil else { return }
        states[size] = .running(fraction: 0, bytesPerSecond: nil, secondsLeft: nil)
        tasks[size] = Task { [modelManager] in
            var previous: (bytes: Int64, at: TimeInterval)? = nil
            do {
                for try await p in modelManager.downloadModelProgress(size) {
                    let now = Date().timeIntervalSinceReferenceDate
                    let (speed, eta) = Self.rate(previous: previous, current: (p.bytesReceived, now), total: p.totalBytes)
                    // Sample the rate at most every half second so it does not flicker.
                    if previous == nil || now - previous!.at >= 0.5 {
                        previous = (p.bytesReceived, now)
                    }
                    states[size] = .running(fraction: p.fraction, bytesPerSecond: speed, secondsLeft: eta)
                }
                states[size] = .done
                onCompleted?(size)
            } catch is CancellationError {
                states[size] = .idle
            } catch {
                states[size] = .failed(error.localizedDescription)
            }
            tasks[size] = nil
        }
    }

    func cancel(_ size: ModelManager.ModelSize) {
        tasks[size]?.cancel()
    }

    /// Bytes per second and seconds left from two samples; nil until there
    /// are two samples or when the total is unknown.
    nonisolated static func rate(
        previous: (bytes: Int64, at: TimeInterval)?,
        current: (bytes: Int64, at: TimeInterval),
        total: Int64
    ) -> (Double?, Double?) {
        guard let previous, current.at > previous.at, current.bytes >= previous.bytes else { return (nil, nil) }
        let speed = Double(current.bytes - previous.bytes) / (current.at - previous.at)
        guard speed > 0, total > current.bytes else { return (speed > 0 ? speed : nil, nil) }
        return (speed, Double(total - current.bytes) / speed)
    }
}
```

- [ ] **Step 7: Generate, build, test — expect PASS** (`Executed 52 tests`).

- [ ] **Step 8: Commit**

```bash
git add SayVoice/App/AppStatus.swift SayVoice/App/AppWindow.swift SayVoice/Features/Settings Tests/SayVoiceTests/SettingsLogicTests.swift SayVoice.xcodeproj
git commit -m "Add AppStatus, AppWindow, settings sections/router and the ModelDownloads coordinator"
```

---

### Task 6: Settings shell — rail, header, General section

**Files:**
- Create: `SayVoice/Features/Settings/SettingsView.swift`, `SettingsRail.swift`, `SectionHeader.swift`, `GeneralSection.swift`
- Test: `Tests/SayVoiceTests/SettingsRenderTests.swift`

**Interfaces:**
- Produces: `SettingsView(settings: SettingsStore, status: AppStatus, router: SettingsRouter, downloads: ModelDownloads, modelManager: ModelManager, onHotkeyChanged:, onHotkeyModeChanged:)`; `static let windowSize = NSSize(width: 780, height: 600)`; sections not yet implemented render a placeholder until Tasks 7–8 (temporary `PlaceholderSection`).
- Consumes: `SettingsRow`, `Card`, `Orb`, `HotkeyRecorder`, `DS.*`.

- [ ] **Step 1: Write the failing render test**

```swift
import SwiftUI
import XCTest
@testable import SayVoice

@MainActor
final class SettingsRenderTests: XCTestCase {

    func makeView(section: SettingsSection) -> SettingsView {
        let settings = SettingsStore()
        let status = AppStatus(); status.modelName = "Large Turbo Q5"
        let router = SettingsRouter(); router.section = section
        let manager = ModelManager()
        return SettingsView(settings: settings, status: status, router: router,
                            downloads: ModelDownloads(modelManager: manager), modelManager: manager,
                            onHotkeyChanged: nil, onHotkeyModeChanged: nil)
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
}
```

`SettingsView.measuredContentHeight(for:hosting:)` is a test hook defined in Step 3: it returns the fitting height of the section content view rendered standalone at the content width (window width − rail − padding).

- [ ] **Step 2: Run to verify failure** — `cannot find 'SettingsView'` in the new module location (the old one has a different init).

- [ ] **Step 3: Create `SettingsView.swift`**

```swift
import AppKit
import SwiftUI

/// Settings window root: icon rail on the left, section header and content
/// on the right. 780 × 600, not resizable; only Recognition may scroll.
struct SettingsView: View {
    static let windowSize = NSSize(width: 780, height: 600)
    static let railWidth: CGFloat = 64
    static let contentPadding: CGFloat = DS.Space.s28

    /// Width available to section content.
    static var contentWidth: CGFloat { windowSize.width - railWidth - 2 * contentPadding }

    let settings: SettingsStore
    let status: AppStatus
    let router: SettingsRouter
    let downloads: ModelDownloads
    let modelManager: ModelManager
    var onHotkeyChanged: ((Hotkey) -> Void)?
    var onHotkeyModeChanged: ((Bool) -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            SettingsRail(selected: router.section) { router.section = $0 }
                .frame(width: Self.railWidth)

            VStack(alignment: .leading, spacing: DS.Space.s20) {
                SectionHeader(section: router.section, status: status)
                sectionContent(router.section)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                Spacer(minLength: 0)
            }
            .padding(Self.contentPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .background(DS.Colors.ground.color)
        .font(DS.font(.body))
    }

    @ViewBuilder
    func sectionContent(_ section: SettingsSection) -> some View {
        switch section {
        case .general:
            GeneralSection(settings: settings, onHotkeyChanged: onHotkeyChanged, onHotkeyModeChanged: onHotkeyModeChanged)
        case .recognition, .dictionary, .insertion, .system:
            PlaceholderSection(section: section)   // replaced in Tasks 7–8
        }
    }

    /// Test hook: fitting height of a section's content at the content width,
    /// rendered on its own so the window frame cannot mask an overflow.
    static func measuredContentHeight(for section: SettingsSection, hosting: NSHostingView<SettingsView>) -> CGFloat {
        let root = hosting.rootView
        let probe = NSHostingView(rootView: AnyView(
            VStack(alignment: .leading, spacing: DS.Space.s20) {
                SectionHeader(section: section, status: root.status)
                root.sectionContent(section)
            }
            .padding(contentPadding)
            .frame(width: windowSize.width - railWidth)
        ))
        probe.appearance = hosting.appearance
        return probe.fittingSize.height
    }
}

/// Temporary stand-in while sections land one by one.
struct PlaceholderSection: View {
    let section: SettingsSection
    var body: some View {
        Card { SettingsRow("\(section.title) — coming in the next task") { EmptyView() } }
    }
}
```

- [ ] **Step 4: Create `SettingsRail.swift`**

```swift
import SwiftUI

/// Icon rail: logo mark on top, one icon per section. The selected item uses
/// the accent (active control); the rest are neutral.
struct SettingsRail: View {
    let selected: SettingsSection
    let onSelect: (SettingsSection) -> Void

    var body: some View {
        VStack(spacing: 6) {
            LogoMark()
                .padding(.top, DS.Space.s12)
                .padding(.bottom, DS.Space.s8)

            ForEach(SettingsSection.allCases) { section in
                Button { onSelect(section) } label: {
                    Image(systemName: section.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(section == selected ? DS.Colors.accent.color : DS.Colors.muted.color)
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(section == selected ? DS.Colors.accentSoft.color : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(section.title)
                .accessibilityLabel(section.title)
                .accessibilityAddTraits(section == selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
        .background(DS.Colors.surface2.color.opacity(0.5))
        .overlay(alignment: .trailing) { Rectangle().fill(DS.Colors.line.color).frame(width: 1) }
    }
}

/// The brand mark: accent gradient tile — the one place besides the orb where
/// the gradient is allowed.
struct LogoMark: View {
    var size: CGFloat = 36
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(LinearGradient(colors: [DS.Colors.accent.color, DS.Colors.accent2.color], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "waveform")
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .shadow(color: DS.Colors.glassShadow.color, radius: 6, x: 0, y: 3)
            .accessibilityLabel("SayVoice")
    }
}
```

- [ ] **Step 5: Create `SectionHeader.swift`**

```swift
import SwiftUI

/// Section title and subtitle on the left, the live status pill on the right.
struct SectionHeader: View {
    let section: SettingsSection
    let status: AppStatus

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: DS.Space.s16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(DS.font(.section))
                    .foregroundStyle(DS.Colors.text.color)
                Text(section.subtitle)
                    .font(DS.font(.body))
                    .foregroundStyle(DS.Colors.muted.color)
            }
            Spacer(minLength: DS.Space.s12)
            StatusPill(status: status)
        }
    }
}

/// "● Ready · Large Turbo Q5" — orb at 10 pt plus text, neutral capsule.
struct StatusPill: View {
    let status: AppStatus

    var body: some View {
        HStack(spacing: DS.Space.s8) {
            Orb(state: status.orbState, size: 10)
            Text(status.pillText)
                .font(DS.font(.valueSmall))
                .foregroundStyle(DS.Colors.muted.color)
        }
        .padding(.leading, 6)
        .padding(.trailing, DS.Space.s12)
        .padding(.vertical, 3)
        .background(Capsule().fill(DS.Colors.surface.color))
        .overlay(Capsule().strokeBorder(DS.Colors.line.color, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
```

- [ ] **Step 6: Create `GeneralSection.swift`**

```swift
import SwiftUI

/// Hotkey card (recorder + Hold/Toggle) and the recording-behaviour card.
struct GeneralSection: View {
    @Bindable var settings: SettingsStore
    var onHotkeyChanged: ((Hotkey) -> Void)?
    var onHotkeyModeChanged: ((Bool) -> Void)?

    var body: some View {
        VStack(spacing: DS.Space.s16) {
            Card(title: "Recording hotkey", subtitle: "A key, a combination or a mouse button") {
                SettingsRow("Hotkey") {
                    HotkeyRecorder(hotkey: $settings.hotkey, onChange: onHotkeyChanged)
                }
                SettingsRow("Mode", note: modeNote) {
                    Picker("", selection: $settings.hotkeyMode) {
                        Text("Hold").tag("hold")
                        Text("Toggle").tag("toggle")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 180)
                    .onChange(of: settings.hotkeyMode) { _, new in onHotkeyModeChanged?(new == "toggle") }
                }
            }

            Card(title: "While recording") {
                SettingsRow("Show the overlay", note: "Glass capsule near the bottom of the screen") {
                    Toggle("", isOn: $settings.overlayEnabled).labelsHidden().toggleStyle(.switch)
                }
                SettingsRow("Sound feedback", note: "A short tone when recording starts and stops") {
                    Toggle("", isOn: $settings.soundFeedback).labelsHidden().toggleStyle(.switch)
                }
            }
        }
    }

    private var modeNote: String {
        settings.hotkeyIsToggle
            ? "Press once to start, again to stop. Needed for buttons that do not report being held, such as those remapped in Logi Options+."
            : "Recording runs while the key or button is held."
    }
}
```

- [ ] **Step 7: Generate, build, test — expect PASS.** If the old `SayVoice/UI/SettingsView.swift` clashes with the new `SettingsView` type name: rename the old struct to `LegacySettingsView` in that file and update the single reference in `AppCoordinator.showSettingsWindow()` (it is deleted in Task 8 anyway).

- [ ] **Step 8: Commit**

```bash
git add SayVoice/Features/Settings SayVoice/UI/SettingsView.swift SayVoice/App/AppCoordinator.swift Tests/SayVoiceTests/SettingsRenderTests.swift SayVoice.xcodeproj
git commit -m "Add the settings shell: rail, section header with status pill, General section"
```

---

### Task 7: Recognition section with in-place download

**Files:**
- Create: `SayVoice/Features/Settings/RecognitionSection.swift`
- Modify: `SayVoice/Features/Settings/SettingsView.swift` (route `.recognition`)
- Test: append to `SettingsRenderTests`

**Interfaces:**
- Consumes: `ModelRow`, `DownloadProgress`, `ModelDownloads`, `SettingsRouter.highlightedModel`, `ModelManager.ModelSize.{displayName, badge, fileSize, qualitySteps, settingsString, recommended}`.

- [ ] **Step 1: Add the failing test**

```swift
    func testRecognitionRendersAndMayScroll() {
        for dark in [true, false] {
            let h = contentHeight(.recognition, dark: dark)
            XCTAssertGreaterThan(h, 200)
            XCTAssertLessThan(h, 1200, "unexpectedly tall — check for a runaway layout")
        }
    }
```

- [ ] **Step 2: Create `RecognitionSection.swift`**

```swift
import SwiftUI

/// Model list with in-place download, then the language picker.
/// The only section allowed to scroll.
struct RecognitionSection: View {
    @Bindable var settings: SettingsStore
    let modelManager: ModelManager
    let downloads: ModelDownloads
    let router: SettingsRouter

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.s16) {
                Card(title: "Model", subtitle: "Larger models are more accurate; all run on this Mac") {
                    VStack(spacing: DS.Space.s8) {
                        ForEach(ModelManager.ModelSize.allCases, id: \.self) { model in
                            ModelRow(
                                name: model.displayName,
                                badge: model == .recommended ? "recommended" : nil,
                                badgeIsAccent: model == .recommended,
                                qualitySteps: model.qualitySteps,
                                sizeText: model.fileSize,
                                isSelected: settings.modelSize == model.settingsString,
                                isDownloaded: modelManager.isModelAvailable(model),
                                isHighlighted: router.highlightedModel == model,
                                download: downloads.state(for: model),
                                onSelect: { settings.modelSize = model.settingsString },
                                onDownload: { downloads.start(model) },
                                onCancel: { downloads.cancel(model) },
                                onRetry: { downloads.start(model) }
                            )
                        }
                    }
                    .padding(.horizontal, DS.Space.s8)
                    .padding(.top, DS.Space.s4)
                }

                Card(title: "Language") {
                    SettingsRow("Recognition language", note: "Set it explicitly when auto-detection gets it wrong — Russian speech with English terms, for example") {
                        Picker("", selection: $settings.language) {
                            Text("Auto").tag("auto")
                            Divider()
                            Text("English").tag("en")
                            Divider()
                            Text("Deutsch").tag("de")
                            Text("Español").tag("es")
                            Text("Français").tag("fr")
                            Text("Italiano").tag("it")
                            Text("Nederlands").tag("nl")
                            Text("Polski").tag("pl")
                            Text("Português").tag("pt")
                            Text("Türkçe").tag("tr")
                            Text("Русский").tag("ru")
                            Text("Українська").tag("uk")
                        }
                        .labelsHidden()
                        .frame(width: 160)
                    }
                }
            }
            .padding(.bottom, DS.Space.s8)
        }
        .scrollIndicators(.automatic)
        .onDisappear { router.highlightedModel = nil }
    }
}
```

In `SettingsView.sectionContent`, route `.recognition` to `RecognitionSection(settings: settings, modelManager: modelManager, downloads: downloads, router: router)` and remove it from the placeholder list.

- [ ] **Step 3: Generate, build, test — expect PASS.**

- [ ] **Step 4: Commit**

```bash
git add SayVoice/Features/Settings Tests/SayVoiceTests/SettingsRenderTests.swift SayVoice.xcodeproj
git commit -m "Add the Recognition section: model rows with in-place download, language picker"
```

---

### Task 8: Dictionary, Insertion, System sections and the licenses sheet; delete the old views

**Files:**
- Create: `SayVoice/Features/Settings/DictionarySection.swift`, `InsertionSection.swift`, `SystemSection.swift`, `LicensesSheet.swift`, `SayVoice/Resources/Licenses/whisper.cpp-LICENSE.txt`
- Modify: `SayVoice/Features/Settings/SettingsView.swift` (routes; remove `PlaceholderSection`)
- Modify: `SayVoice/App/AppCoordinator.swift` (own `AppStatus`/`SettingsRouter`/`ModelDownloads`; `showSettings(section:highlight:)`; remove `showModelDownloadWindow` and `downloadWindow`; update `state` to `status`; model-missing paths)
- Modify: `SayVoice/UI/MenuBarController.swift` (remove the download item and callback)
- Delete: `SayVoice/UI/LegacySettingsView.swift` (the old settings view, renamed in Task 6), `SayVoice/ModelManagement/ModelDownloadView.swift`
- Test: append to `SettingsRenderTests`

**Interfaces:**
- Produces: `AppCoordinator.showSettings(section: SettingsSection = .general, highlight: ModelManager.ModelSize? = nil)`.

- [ ] **Step 1: Add the failing tests**

```swift
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
```

- [ ] **Step 2: Add the whisper.cpp licence file**

`SayVoice/Resources/Licenses/whisper.cpp-LICENSE.txt`:

```
MIT License

Copyright (c) 2023-2024 The ggml authors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

`project.yml`: no change needed — files under `SayVoice/` that are not sources are bundled as resources (flat, top level of `Contents/Resources`).

- [ ] **Step 3: Create the three sections**

`DictionarySection.swift`:

```swift
import SwiftUI

struct DictionarySection: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Card(title: "Terms", subtitle: "Names and jargon the model should write exactly as given") {
            VStack(alignment: .leading, spacing: DS.Space.s8) {
                TagField(text: $settings.vocabularyPrompt, placeholder: "Add term")
                Text("Enter or comma adds a term, Backspace removes the last one. Terms are wrapped into a punctuated sentence before they reach the model, so they never change how it punctuates your speech. Empty = off.")
                    .font(DS.font(.caption))
                    .foregroundStyle(DS.Colors.muted.color)
            }
            .padding(.horizontal, DS.Space.s16)
            .padding(.top, DS.Space.s4)
        }
    }
}
```

`InsertionSection.swift`:

```swift
import SwiftUI

struct InsertionSection: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Card(title: "Insertion") {
            SettingsRow("Method", note: methodNote) {
                Picker("", selection: $settings.pasteMethod) {
                    Text("Clipboard").tag("pasteboard")
                    Text("Accessibility").tag("ax")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }
            SettingsRow("Restore the clipboard after pasting", note: restoreNote) {
                Toggle("", isOn: $settings.restorePasteboard).labelsHidden().toggleStyle(.switch)
            }
        }
    }

    private var methodNote: String {
        settings.pasteMethod == "ax"
            ? "Writes straight into the focused field through the accessibility API; the clipboard is untouched. Works in native apps (TextEdit, Notes, Xcode, Safari). Chrome, Electron and Terminal do not expose it — there, insertion falls back to the clipboard."
            : "Puts the text on the clipboard and sends ⌘V. Works everywhere paste works."
    }

    private var restoreNote: String {
        settings.restorePasteboard
            ? "Whatever was on the clipboard — including images and files — is put back after pasting. ⌘V then pastes that, not the dictation; the last dictation is always in History."
            : "The dictated text stays on the clipboard so ⌘V repeats it. Whatever was there before is lost, including images and files."
    }
}
```

`SystemSection.swift`:

```swift
import AppKit
import SwiftUI

struct SystemSection: View {
    @Bindable var settings: SettingsStore
    @State private var showingLicenses = false

    /// Public repository; shown as a link in System.
    static let repositoryURL = URL(string: "https://github.com/ashnurkoff/SayVoice")!

    var body: some View {
        VStack(spacing: DS.Space.s16) {
            Card(title: "Startup") {
                SettingsRow("Open at login") {
                    Toggle("", isOn: $settings.launchAtLogin).labelsHidden().toggleStyle(.switch)
                }
            }
            Card(title: "About") {
                SettingsRow("Version") {
                    Text(Self.versionText).font(DS.font(.valueSmall)).foregroundStyle(DS.Colors.muted.color)
                }
                SettingsRow("Source code", note: "SayVoice is open source") {
                    Button("Open on GitHub") { NSWorkspace.shared.open(Self.repositoryURL) }.buttonStyle(.dsLink)
                }
                SettingsRow("Licenses", note: "whisper.cpp, Onest, JetBrains Mono") {
                    Button("Show") { showingLicenses = true }.buttonStyle(.dsSecondary)
                }
            }
        }
        .sheet(isPresented: $showingLicenses) { LicensesSheet() }
    }

    static var versionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
```

`LicensesSheet.swift`:

```swift
import SwiftUI

/// Third-party licences, read from the bundle so the text shown is the text shipped.
struct LicensesSheet: View {
    @Environment(\.dismiss) private var dismiss

    struct Item: Identifiable {
        let name: String
        let license: String
        let text: String
        var id: String { name }
    }

    static let items: [Item] = [
        Item(name: "whisper.cpp", license: "MIT", text: load("whisper.cpp-LICENSE", subdirectory: nil)),
        Item(name: "Onest", license: "SIL Open Font License 1.1", text: load("Onest-OFL", subdirectory: "Fonts")),
        Item(name: "JetBrains Mono", license: "SIL Open Font License 1.1", text: load("JetBrainsMono-OFL", subdirectory: "Fonts")),
    ]

    private static func load(_ name: String, subdirectory: String?) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: subdirectory),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            HStack {
                Text("Licenses").font(DS.font(.title)).foregroundStyle(DS.Colors.text.color)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.dsSecondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s20) {
                    ForEach(Self.items) { item in
                        VStack(alignment: .leading, spacing: DS.Space.s8) {
                            HStack(spacing: DS.Space.s8) {
                                Text(item.name).font(DS.font(.bodyMedium)).foregroundStyle(DS.Colors.text.color)
                                Chip(item.license)
                            }
                            Text(item.text)
                                .font(DS.font(.caption))
                                .foregroundStyle(DS.Colors.muted.color)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(DS.Space.s20)
        .frame(width: 560, height: 480)
        .background(DS.Colors.ground.color)
    }
}
```

Route the three sections in `SettingsView.sectionContent` and delete `PlaceholderSection`.

- [ ] **Step 4: Coordinator wiring**

In `SayVoice/App/AppCoordinator.swift`:

1. Properties: remove `private var downloadWindow: NSWindow?`; add
```swift
    private let status = AppStatus()
    private let settingsRouter = SettingsRouter()
    private lazy var modelDownloads = ModelDownloads(modelManager: modelManager)
```
2. In `start()`: delete the `menuBarController?.onDownloadModel = …` line; after `hotkeyListener?.apply(isToggle:)` add
```swift
        status.modelName = (ModelManager.ModelSize(settingsString: settingsStore.modelSize) ?? .recommended).displayName
        modelDownloads.onCompleted = { [weak self] _ in
            guard let self else { return }
            if case .error(.modelNotLoaded) = self.state { self.state = .idle }
        }
```
3. `handleStateChange`: first line after `menuBarController?.setState(new)` add `status.state = new`.
4. Replace `showModelDownloadWindow()` (the whole method) and both call sites: in `continueStartupAfterAccessibility` and in the `.modelNotLoaded` catch, call `showSettings(section: .recognition, highlight: modelSize)` (in the catch, compute `let modelSize = ModelManager.ModelSize(settingsString: settingsStore.modelSize) ?? .recommended` first).
5. Replace `showSettingsWindow()` with:
```swift
    func showSettings(section: SettingsSection = .general, highlight: ModelManager.ModelSize? = nil) {
        settingsRouter.section = section
        settingsRouter.highlightedModel = highlight
        status.modelName = (ModelManager.ModelSize(settingsString: settingsStore.modelSize) ?? .recommended).displayName

        if let existing = settingsWindow, existing.isVisible {
            AppWindow.present(existing)
            return
        }
        let view = SettingsView(
            settings: settingsStore, status: status, router: settingsRouter,
            downloads: modelDownloads, modelManager: modelManager,
            onHotkeyChanged: { [weak self] hotkey in self?.hotkeyListener?.apply(hotkey) },
            onHotkeyModeChanged: { [weak self] isToggle in self?.hotkeyListener?.apply(isToggle: isToggle) }
        )
        let window = AppWindow.make(title: "SayVoice Settings", size: SettingsView.windowSize, content: view)
        AppWindow.present(window)
        settingsWindow = window
    }
```
   and update `menuBarController?.onShowSettings = { [weak self] in self?.showSettings() }`.
6. `status.modelName` must follow the selection: in `showSettings` it is refreshed on open; additionally, in `handleKeyUp` before transcribing, set `status.modelName = modelSize.displayName`.

In `SayVoice/UI/MenuBarController.swift`: delete the `downloadItem` three lines and the separator after it in `setupMenu()`, the `var onDownloadModel` property and `handleDownloadModel()`.

- [ ] **Step 5: Delete the old views**

```bash
git rm -q SayVoice/UI/LegacySettingsView.swift SayVoice/ModelManagement/ModelDownloadView.swift
```

- [ ] **Step 6: Generate, build, test — expect PASS** (`Executed 56 tests`).

- [ ] **Step 7: Commit**

```bash
git add -A SayVoice/Features/Settings SayVoice/Resources/Licenses SayVoice/App/AppCoordinator.swift SayVoice/UI Tests/SayVoiceTests/SettingsRenderTests.swift SayVoice/ModelManagement SayVoice.xcodeproj
git commit -m "Complete the settings window and remove the model download window

Dictionary, Insertion and System sections join General and Recognition.
A missing model now opens Settings → Recognition with the row highlighted
instead of a separate window; the menu bar loses its download item."
```

---

### Task 9: Phase wrap-up — guards, spec alignment, plan alignment

**Files:**
- Modify: `docs/superpowers/specs/2026-09-09-ui-redesign-design.md` §3.4, §5.1, §5.5
- Verification only otherwise.

- [ ] **Step 1: Guards**

```bash
grep -rn "ModelDownloadView\|HotkeyRecorderField\|showModelDownloadWindow\|onDownloadModel\|LegacySettingsView\|LegacyModelRow\|PlaceholderSection" SayVoice Tests || echo "no stale symbols"
grep -rln "[А-Яа-яЁё]" SayVoice/DesignSystem SayVoice/Features Tests SayVoice/App/AppStatus.swift SayVoice/App/AppWindow.swift || echo "no Cyrillic in new files"
grep -rn "Color(red:\|Color(nsColor:\|\.blue\b\|\.purple\b\|\.orange\b\|\.green\b" SayVoice/DesignSystem/Components SayVoice/Features/Settings || echo "no literal colours"
grep -rn "SettingsStore\|ModelManager\|Hotkey\b\|AppCoordinator" SayVoice/DesignSystem || echo "design system references no feature types"
xcodegen generate && git diff --exit-code --stat SayVoice.xcodeproj && echo "project in sync"
```

Expected: the five "no …"/"in sync" lines.

- [ ] **Step 2: Spec alignment**

- §3.4: replace "Overlay result auto-dismiss: 2 s, cancelled while the pointer is over the panel." with "Overlay result auto-dismiss: 2 s, paused while the pointer is over the panel (at most 10 s). Error cards: 3 s, or 8 s when they carry an action; tapping the action dismisses."
- §5.1, after the Recognition bullet, add: "The default model on a fresh install is Large Turbo Q5 (`ModelSize.recommended`)."
- §6 folder tree: move `HotkeyRecorder.swift` from `DesignSystem/Components/` to `Features/Settings/` (it depends on the `Hotkey` type); add `TagField.swift` under `DesignSystem/Components/` if it is not listed there.
- §4, the sentence listing removed components (`Badge`, `TagChip`, `StopButton` …): remove `TagChip` from that list — it stays private to `TagField`.
- §7 (component consolidation): the line saying `TagChip` → `Chip` becomes "`TagChip` stays private to `TagField` — a removable chip with a hover state is not a `Chip`; both use the same tokens."
- §5.5: replace the paragraph with: "The separate window and `ModelDownloadView.swift` are removed. When the selected model is missing at launch or at transcription time, the app opens Settings → Recognition with that model's row outlined (`warn` border) and its `DownloadProgress` ready; `ModelDownloads` owns the transfer and cancellation. Onboarding (Phase 3) uses the same component and coordinator."

- [ ] **Step 3: Full suite and Release build**

```bash
xcodebuild -project SayVoice.xcodeproj -scheme SayVoice -derivedDataPath build test 2>&1 | grep -E "Executed|failed" | tail -2
xcodebuild -project SayVoice.xcodeproj -scheme SayVoice -configuration Release -derivedDataPath build build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-09-09-ui-redesign-design.md
git commit -m "Align the spec with phase 2: default model, in-place download, dismiss timings"
```

---

## Self-review

**Spec coverage (Phase 2 scope):** §4 `ModelRow`, `DownloadProgress` → Tasks 2–3; `TagField`, `HotkeyRecorder` restyle → Task 4; §5.1 window, rail, five sections, header pill, Recognition-only scroll → Tasks 6–8; §5.5 no separate download window → Task 8; §6 `AppWindow` → Task 5 (used by settings now, onboarding in Phase 3); `EmptyState` → Phase 3 (history). `SystemSection` "Licenses" sheet → Task 8. §9 tests → every task.

**Placeholder scan:** none; every code step carries the full file or exact replacement.

**Type consistency:** `DownloadState` cases used identically in Tasks 2, 3, 5, 7; `ModelRow` init labels match between Task 3 and Task 7; `ModelDownloads.state(for:)/start/cancel/onCompleted` match Tasks 5, 7, 8; `AppStatus.pillText/orbState` match Tasks 5, 6; `SettingsView` init labels match Tasks 6, 8 and the test; `SettingsView.measuredContentHeight(for:hosting:)` declared in Task 6 and used in the Task 6 test; `AppWindow.make/present` match Tasks 5, 8; `ModelManager.ModelSize.recommended/qualitySteps` match Tasks 1, 7, 8; `downloadModelProgress` consumed in Task 5.

**Known risks for the executor:** (1) `ModelDownloads` mutates `states` from within a `Task` created on the main actor — the class is `@MainActor`, so the task inherits isolation; do not add `Task.detached`. (2) `Picker(.segmented)` inside `SettingsRow` needs `.labelsHidden()` or the Form-style label repositioning seen in Phase 1 reappears. (3) The `SettingsRenderTests` measure fitting heights; if a section overflows 600 pt, reduce `Card` internal padding before shrinking type sizes — the type scale is fixed by the spec.
