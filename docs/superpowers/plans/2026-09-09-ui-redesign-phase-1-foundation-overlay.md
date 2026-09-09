# UI Redesign — Phase 1: Foundation + Overlay — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put the new design system into the app (tokens, fonts, base components, test target) and migrate the recording overlay — the most visible surface — onto it, so that the app ships a coherent overlay in all four states and both themes while the rest of the UI keeps working unchanged.

**Architecture:** A `DesignSystem` module-in-folder (tokens + components, no dependency on stores or features) is added under `SayVoice/DesignSystem/`. The overlay moves to `SayVoice/Features/Overlay/` and is rebuilt from those components, keeping the existing `OverlayWindowController` positioning logic and the existing public API used by `AppCoordinator` (with two small additions: result actions and an error action). A `SayVoiceTests` unit-test target is added; the app skips its own startup when hosted by XCTest.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI + AppKit, macOS 26 (Liquid Glass via `glassEffect`), XcodeGen 2.46, XCTest. Fonts: Onest and JetBrains Mono (variable TTF, OFL-1.1).

**Spec:** `docs/superpowers/specs/2026-09-09-ui-redesign-design.md` — sections 3 (tokens), 4 (components), 5.2 (overlay), 6 (architecture), 9 (testing). Phases 2–3 (settings, onboarding, history, menu bar, cleanup) get their own plans after this one lands.

## Global Constraints

- Deployment target **macOS 26.0**; no `#available` branches for older systems.
- **All new and rewritten files are in English** — UI strings, comments, identifiers. Files not touched by this plan keep their current language.
- **No third-party UI libraries.** Pure SwiftUI/AppKit.
- `DesignSystem/` files import only `SwiftUI`, `AppKit`, `CoreText`. They never import or reference `SettingsStore`, `ModelManager`, `AppCoordinator`, `OverlayModel` or any other feature/app type.
- Colours are used only through `DS.Colors.*` tokens; no colour literals outside `Colors.swift`. Fonts only through `DS.font(_:)`.
- **Three-places rule:** the accent colour appears only as (1) the orb/logo, (2) the active control, (3) the glass border.
- Commit after every task. Commit messages in English, imperative, no AI attribution lines.
- Do not touch: `Audio/`, `Transcription/`, `TextInjection/`, `HotkeyListener/`, `Permissions/`, `History/`, `Settings/`, `Packages/`.
- The project is generated: after adding/moving files run `xcodegen generate` before building. The generated `SayVoice.xcodeproj` is still tracked at this phase — commit its changes together with the source changes.
- Build command used throughout: `xcodebuild -project SayVoice.xcodeproj -scheme SayVoice -configuration Release -derivedDataPath build build 2>&1 | grep -E "error:|BUILD"`.
- Test command: `xcodebuild -project SayVoice.xcodeproj -scheme SayVoice -derivedDataPath build test 2>&1 | grep -E "error:|Test Case|Executed|FAILED|passed|failed" | tail -40`.
- Install for live checks: `osascript -e 'quit app "SayVoice"'; sleep 2; rm -rf /Applications/SayVoice.app && cp -R build/Build/Products/Release/SayVoice.app /Applications/ && open /Applications/SayVoice.app`.

---

## File structure

**Created**

| Path | Responsibility |
|---|---|
| `SayVoice/DesignSystem/Tokens/Colors.swift` | `DS` namespace, `DSColor` (dark/light pair → `NSColor`/`Color`), all colour tokens |
| `SayVoice/DesignSystem/Tokens/Typography.swift` | `DS.TextStyle`, `DS.font(_:)`, font availability with system fallback |
| `SayVoice/DesignSystem/Tokens/Spacing.swift` | `DS.Space`, `DS.Radius`, `DS.Size` |
| `SayVoice/DesignSystem/Tokens/Motion.swift` | `DS.Motion` animations and durations |
| `SayVoice/DesignSystem/Components/Buttons.swift` | `.dsPrimary`, `.dsSecondary`, `.dsLink`, `.dsDestructive` button styles |
| `SayVoice/DesignSystem/Components/Chip.swift` | Small capsule label, 4 styles |
| `SayVoice/DesignSystem/Components/KeyCap.swift` | Monospace hotkey display |
| `SayVoice/DesignSystem/Components/Orb.swift` | State indicator with pulse/breath, reduce-motion aware |
| `SayVoice/DesignSystem/Components/GlassPanel.swift` | Liquid Glass container, capsule or card |
| `SayVoice/DesignSystem/Components/Card.swift` | Settings card with optional header |
| `SayVoice/DesignSystem/Components/SettingsRow.swift` | Label + note + trailing control, 44pt |
| `SayVoice/DesignSystem/Components/Waveform.swift` | Live bars + `BarEngine` smoothing (moved from old overlay) |
| `SayVoice/Features/Overlay/OverlayModel.swift` | Moved from `UI/`; gains result/error action closures and hover flag |
| `SayVoice/Features/Overlay/OverlayWindowController.swift` | Moved from `UI/`; result/error accept mouse, hover defers dismiss |
| `SayVoice/Features/Overlay/OverlayView.swift` | Root: `Color.clear` backing + `GlassPanel` + state switch |
| `SayVoice/Features/Overlay/RecordingContent.swift` | Orb + labels + waveform + timer (+ Stop in toggle mode) |
| `SayVoice/Features/Overlay/TranscribingContent.swift` | Orb + label + indeterminate bar |
| `SayVoice/Features/Overlay/ResultContent.swift` | Orb + text (4 lines) + Copy / Show all / duration |
| `SayVoice/Features/Overlay/ErrorContent.swift` | Orb + message + optional action |
| `SayVoice/Resources/Fonts/Onest[wght].ttf`, `Onest-OFL.txt`, `JetBrainsMono[wght].ttf`, `JetBrainsMono-OFL.txt` | Bundled fonts + licences |
| `Tests/SayVoiceTests/*.swift` | Unit tests (see tasks) |

**Modified**

| Path | Change |
|---|---|
| `project.yml` | Target 26.0, Xcode 26, fonts folder reference, `SayVoiceTests` target, scheme test target |
| `SayVoice/Resources/Info.plist` | `ATSApplicationFontsPath = Fonts` |
| `SayVoice/App/SayVoiceApp.swift` | Skip `AppCoordinator.start()` under XCTest |
| `SayVoice/App/AppCoordinator.swift` | Pass duration + actions to `showResult`, action to `showError`, use `menuBarController.showHistory()` |
| `SayVoice/UI/MenuBarController.swift` | `showPopover()` becomes internal `showHistory()` |

**Deleted**

| Path | Replaced by |
|---|---|
| `SayVoice/UI/OverlayView.swift` (435 lines) | `Features/Overlay/*Content.swift` + `DesignSystem` components |
| `SayVoice/UI/OverlayModel.swift`, `SayVoice/UI/OverlayWindowController.swift` | moved to `Features/Overlay/` |

`SayVoice/UI/` keeps `SettingsView`, `TagField`, `HotkeyRecorderField`, `OnboardingView`, `HistoryPopoverView`, `MenuBarController` until Phases 2–3. That is a known transitional state.

---

### Task 1: Project configuration, fonts, test target, XCTest guard

**Files:**
- Modify: `project.yml`
- Modify: `SayVoice/Resources/Info.plist`
- Modify: `SayVoice/App/SayVoiceApp.swift:14-20`
- Create: `SayVoice/Resources/Fonts/Onest[wght].ttf`, `SayVoice/Resources/Fonts/Onest-OFL.txt`, `SayVoice/Resources/Fonts/JetBrainsMono[wght].ttf`, `SayVoice/Resources/Fonts/JetBrainsMono-OFL.txt`
- Create: `Tests/SayVoiceTests/FontsTests.swift`

**Interfaces:**
- Produces: a `SayVoiceTests` target hosted by the app, with `@testable import SayVoice` working; fonts "Onest" and "JetBrains Mono" registered at launch.

- [ ] **Step 1: Download the fonts and licences**

```bash
mkdir -p SayVoice/Resources/Fonts
curl -sSL -o "SayVoice/Resources/Fonts/Onest[wght].ttf"        "https://github.com/google/fonts/raw/main/ofl/onest/Onest%5Bwght%5D.ttf"
curl -sSL -o "SayVoice/Resources/Fonts/Onest-OFL.txt"           "https://github.com/google/fonts/raw/main/ofl/onest/OFL.txt"
curl -sSL -o "SayVoice/Resources/Fonts/JetBrainsMono[wght].ttf" "https://github.com/google/fonts/raw/main/ofl/jetbrainsmono/JetBrainsMono%5Bwght%5D.ttf"
curl -sSL -o "SayVoice/Resources/Fonts/JetBrainsMono-OFL.txt"   "https://github.com/google/fonts/raw/main/ofl/jetbrainsmono/OFL.txt"
ls -la SayVoice/Resources/Fonts/
file "SayVoice/Resources/Fonts/Onest[wght].ttf" "SayVoice/Resources/Fonts/JetBrainsMono[wght].ttf"
```

Expected: four files; both `.ttf` reported as `TrueType Font data`, sizes ≈193 KB and ≈187 KB.

- [ ] **Step 2: Rewrite `project.yml`**

Replace the whole file with:

```yaml
name: SayVoice
options:
  bundleIdPrefix: com.sayvoice
  deploymentTarget:
    macOS: "26.0"
  xcodeVersion: "26.0"
  generateEmptyDirectories: true

settings:
  base:
    SWIFT_VERSION: "6.0"
    MACOSX_DEPLOYMENT_TARGET: "26.0"
    SWIFT_STRICT_CONCURRENCY: complete

packages:
  CWhisper:
    path: Packages/CWhisper

targets:
  SayVoice:
    type: application
    platform: macOS
    sources:
      - path: SayVoice
        excludes:
          - Resources/Info.plist
          - Resources/Fonts
      # Folder reference: copied into Contents/Resources/Fonts as a folder,
      # which is what ATSApplicationFontsPath in Info.plist points at.
      - path: SayVoice/Resources/Fonts
        type: folder
        buildPhase: resources
    dependencies:
      - package: CWhisper
        product: WhisperSwift
    scheme:
      testTargets:
        - SayVoiceTests
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.sayvoice.app
        PRODUCT_NAME: SayVoice
        INFOPLIST_FILE: SayVoice/Resources/Info.plist
        CODE_SIGN_ENTITLEMENTS: SayVoice/Resources/SayVoice.entitlements
        CODE_SIGN_IDENTITY: "-"
        CODE_SIGN_STYLE: Manual
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ENABLE_HARDENED_RUNTIME: false
        COMBINE_HIDPI_IMAGES: true

  SayVoiceTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: Tests/SayVoiceTests
    dependencies:
      - target: SayVoice
    settings:
      base:
        SWIFT_VERSION: "6.0"
        SWIFT_STRICT_CONCURRENCY: complete
        CODE_SIGN_IDENTITY: "-"
        CODE_SIGN_STYLE: Manual
```

- [ ] **Step 3: Register the fonts folder in `Info.plist`**

Add before the closing `</dict>`:

```xml
	<key>ATSApplicationFontsPath</key>
	<string>Fonts</string>
```

- [ ] **Step 4: Skip app startup under XCTest**

In `SayVoice/App/SayVoiceApp.swift`, replace `applicationDidFinishLaunching`:

```swift
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Under XCTest the app is only a host process for unit tests:
        // no event tap, no permission prompts, no windows.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }

        coordinator = AppCoordinator()
        coordinator?.start()
    }
```

- [ ] **Step 5: Write the failing font test**

Create `Tests/SayVoiceTests/FontsTests.swift`:

```swift
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
```

- [ ] **Step 6: Generate the project and run the tests — expect PASS**

```bash
xcodegen generate
xcodebuild -project SayVoice.xcodeproj -scheme SayVoice -derivedDataPath build test 2>&1 | grep -E "error:|Test Case|Executed|FAILED|passed|failed" | tail -20
```

Expected: `Executed 2 tests, with 0 failures`. If `Onest not registered`: check `build/Build/Products/Debug/SayVoice.app/Contents/Resources/Fonts/` exists and contains the two `.ttf` files (folder reference), and that `Info.plist` in the built app has `ATSApplicationFontsPath`.

- [ ] **Step 7: Build Release and confirm the app still launches**

```bash
xcodebuild -project SayVoice.xcodeproj -scheme SayVoice -configuration Release -derivedDataPath build build 2>&1 | grep -E "error:|BUILD"
ls build/Build/Products/Release/SayVoice.app/Contents/Resources/Fonts/
```

Expected: `BUILD SUCCEEDED`; the `Fonts` folder lists both `.ttf` files.

- [ ] **Step 8: Commit**

```bash
git add project.yml SayVoice/Resources/Info.plist SayVoice/App/SayVoiceApp.swift SayVoice/Resources/Fonts Tests SayVoice.xcodeproj
git commit -m "Target macOS 26, bundle Onest and JetBrains Mono, add unit test target

Raises the deployment target to 26.0 as decided in the UI redesign spec.
Fonts are shipped as a folder reference registered through
ATSApplicationFontsPath; both are OFL-1.1 and their licences sit next to
the files. The app skips AppCoordinator startup when hosted by XCTest so
unit tests do not install an event tap or prompt for permissions."
```

---

### Task 2: Colour, typography, spacing and motion tokens

**Files:**
- Create: `SayVoice/DesignSystem/Tokens/Colors.swift`
- Create: `SayVoice/DesignSystem/Tokens/Typography.swift`
- Create: `SayVoice/DesignSystem/Tokens/Spacing.swift`
- Create: `SayVoice/DesignSystem/Tokens/Motion.swift`
- Test: `Tests/SayVoiceTests/DesignTokensTests.swift`

**Interfaces:**
- Produces:
  - `enum DS` namespace.
  - `struct DSColor: Sendable { var nsColor: NSColor; var color: Color; func resolved(for appearance: NSAppearance) -> NSColor }`
  - `DS.Colors.{ground, surface, surface2, line, text, muted, faint, accent, accent2, accentSoft, rec, ok, warn, glassFill, glassLine, glassHighlight}: DSColor`
  - `enum DS.TextStyle { display, section, title, bodyLarge, body, bodyMedium, caption, value, valueSmall }`
  - `DS.font(_ style: DS.TextStyle) -> Font`
  - `DS.Space.{s4,s8,s12,s16,s20,s28}: CGFloat`, `DS.Radius.{control=6,row=10,card=14,overlayCard=18}`, `DS.Size.{settingsRow=44,popoverRow=48,overlayWidth=420}`
  - `DS.Motion.{stateChange: Animation, orb: Animation, pulseDuration=1.2, breathDuration=1.6, resultAutoDismiss=2.0}`

- [ ] **Step 1: Write the failing token tests**

Create `Tests/SayVoiceTests/DesignTokensTests.swift`:

```swift
import AppKit
import XCTest
@testable import SayVoice

final class DesignTokensTests: XCTestCase {

    private func hex(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB)!
        return String(format: "#%02X%02X%02X", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }

    func testGroundResolvesPerAppearance() {
        XCTAssertEqual(hex(DS.Colors.ground.resolved(for: NSAppearance(named: .darkAqua)!)), "#17171D")
        XCTAssertEqual(hex(DS.Colors.ground.resolved(for: NSAppearance(named: .aqua)!)), "#F7F7FB")
    }

    func testAccentResolvesPerAppearance() {
        XCTAssertEqual(hex(DS.Colors.accent.resolved(for: NSAppearance(named: .darkAqua)!)), "#7B7FF2")
        XCTAssertEqual(hex(DS.Colors.accent.resolved(for: NSAppearance(named: .aqua)!)), "#5B5FD6")
    }

    func testLineIsTranslucent() {
        let dark = DS.Colors.line.resolved(for: NSAppearance(named: .darkAqua)!).usingColorSpace(.sRGB)!
        XCTAssertEqual(dark.alphaComponent, 0.07, accuracy: 0.005)
        XCTAssertEqual(dark.redComponent, 1.0, accuracy: 0.001)
    }

    func testFontsUseBundledFacesWhenAvailable() {
        XCTAssertTrue(DS.Typography.isOnestAvailable)
        XCTAssertTrue(DS.Typography.isMonoAvailable)
    }

    func testSpacingScale() {
        XCTAssertEqual([DS.Space.s8, DS.Space.s12, DS.Space.s16, DS.Space.s20, DS.Space.s28], [8, 12, 16, 20, 28])
        XCTAssertEqual(DS.Size.overlayWidth, 420)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodegen generate
xcodebuild -project SayVoice.xcodeproj -scheme SayVoice -derivedDataPath build test 2>&1 | grep -E "error:" | head -5
```

Expected: compile errors `cannot find 'DS' in scope`.

- [ ] **Step 3: Create `Colors.swift`**

```swift
import AppKit
import SwiftUI

/// Namespace for the design system: tokens and shared helpers.
/// Components live in `DesignSystem/Components` and use only these tokens.
enum DS {}

/// A colour with one value per appearance. Stored as plain numbers so the
/// value is `Sendable` and safe as a global constant under strict
/// concurrency; the `NSColor` is built on access, which is cheap.
struct DSColor: Sendable {
    let darkHex: UInt32
    let darkAlpha: Double
    let lightHex: UInt32
    let lightAlpha: Double

    init(dark: UInt32, light: UInt32, darkAlpha: Double = 1, lightAlpha: Double = 1) {
        self.darkHex = dark
        self.darkAlpha = darkAlpha
        self.lightHex = light
        self.lightAlpha = lightAlpha
    }

    /// Dynamic colour that follows the effective appearance of the view it is drawn in.
    var nsColor: NSColor {
        let dark = Self.make(darkHex, darkAlpha)
        let light = Self.make(lightHex, lightAlpha)
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    var color: Color { Color(nsColor: nsColor) }

    /// Concrete colour for a given appearance — for tests and for AppKit
    /// drawing code that resolves colours itself (status icons).
    func resolved(for appearance: NSAppearance) -> NSColor {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? Self.make(darkHex, darkAlpha)
            : Self.make(lightHex, lightAlpha)
    }

    private static func make(_ hex: UInt32, _ alpha: Double) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension DS {
    /// Colour roles. Values come from the design spec §3.1; components never
    /// use literals, only these roles.
    enum Colors {
        // Grounds and surfaces
        static let ground   = DSColor(dark: 0x17171D, light: 0xF7F7FB)
        static let surface  = DSColor(dark: 0x202029, light: 0xFFFFFF)
        static let surface2 = DSColor(dark: 0x282833, light: 0xF2F2F8)
        static let line     = DSColor(dark: 0xFFFFFF, light: 0x000000, darkAlpha: 0.07, lightAlpha: 0.08)

        // Exactly three text levels
        static let text  = DSColor(dark: 0xF1F1F6, light: 0x191A22)
        static let muted = DSColor(dark: 0x9E9FB0, light: 0x6A6C80)
        static let faint = DSColor(dark: 0x64667A, light: 0xA7A9BA)

        // Brand — see the three-places rule in the spec
        static let accent     = DSColor(dark: 0x7B7FF2, light: 0x5B5FD6)
        static let accent2    = DSColor(dark: 0xA78BFA, light: 0x8B5CF6)
        static let accentSoft = DSColor(dark: 0x7B7FF2, light: 0x5B5FD6, darkAlpha: 0.16, lightAlpha: 0.12)

        // Semantic — separate from the accent
        static let rec  = DSColor(dark: 0xF5636F, light: 0xE8465A)
        static let ok   = DSColor(dark: 0x3ECF8E, light: 0x22A86B)
        static let warn = DSColor(dark: 0xE0A34A, light: 0xC4842A)

        // Glass (overlay)
        static let glassFill      = DSColor(dark: 0x202029, light: 0xFFFFFF, darkAlpha: 0.62, lightAlpha: 0.62)
        static let glassLine      = DSColor(dark: 0x7B7FF2, light: 0x5B5FD6, darkAlpha: 0.28, lightAlpha: 0.30)
        static let glassHighlight = DSColor(dark: 0xFFFFFF, light: 0xFFFFFF, darkAlpha: 0.22, lightAlpha: 0.95)
        // Overlay drop shadow: indigo-tinted on dark, plain on light
        static let glassShadow    = DSColor(dark: 0x281E78, light: 0x000000, darkAlpha: 0.35, lightAlpha: 0.18)
    }
}
```

- [ ] **Step 4: Create `Typography.swift`**

```swift
import CoreText
import SwiftUI

extension DS {
    /// Text styles from the design spec §3.2. Sizes and weights are fixed here
    /// so screens never pick their own.
    enum TextStyle {
        case display      // 24 / 700  onboarding step title
        case section      // 22 / 700  settings section title
        case title        // 17 / 600  card title, popover header
        case bodyLarge    // 15 / 500  overlay result, primary labels
        case body         // 13 / 400
        case bodyMedium   // 13 / 500
        case caption      // 12 / 400  explanatory notes
        case value        // 14 / 500  mono: timer, hotkey caps
        case valueSmall   // 12 / 500  mono: sizes, durations, language tags
    }

    enum Typography {
        static let textFamily = "Onest"
        static let monoFamily = "JetBrains Mono"

        /// True when the bundled face is registered. Checked through CoreText,
        /// which is safe off the main thread.
        static var isOnestAvailable: Bool { isFamilyAvailable(textFamily) }
        static var isMonoAvailable: Bool { isFamilyAvailable(monoFamily) }

        private static func isFamilyAvailable(_ family: String) -> Bool {
            ((CTFontManagerCopyAvailableFontFamilyNames() as? [String]) ?? []).contains(family)
        }
    }

    static func font(_ style: TextStyle) -> Font {
        switch style {
        case .display:    return text(24, .bold)
        case .section:    return text(22, .bold)
        case .title:      return text(17, .semibold)
        case .bodyLarge:  return text(15, .medium)
        case .body:       return text(13, .regular)
        case .bodyMedium: return text(13, .medium)
        case .caption:    return text(12, .regular)
        case .value:      return mono(14, .medium)
        case .valueSmall: return mono(12, .medium)
        }
    }

    /// Onest with a silent system fallback if the bundled font is missing.
    private static func text(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        Typography.isOnestAvailable
            ? Font.custom(Typography.textFamily, size: size).weight(weight)
            : Font.system(size: size, weight: weight)
    }

    /// JetBrains Mono with tabular digits; falls back to the system monospaced face.
    private static func mono(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        let base = Typography.isMonoAvailable
            ? Font.custom(Typography.monoFamily, size: size).weight(weight)
            : Font.system(size: size, weight: weight, design: .monospaced)
        return base.monospacedDigit()
    }
}
```

- [ ] **Step 5: Create `Spacing.swift` and `Motion.swift`**

`Spacing.swift`:

```swift
import CoreGraphics

extension DS {
    /// Spacing scale, base unit 4 (spec §3.3).
    enum Space {
        static let s4: CGFloat = 4
        static let s8: CGFloat = 8
        static let s12: CGFloat = 12
        static let s16: CGFloat = 16
        static let s20: CGFloat = 20
        static let s28: CGFloat = 28
    }

    enum Radius {
        static let control: CGFloat = 6      // small controls, key caps
        static let row: CGFloat = 10
        static let card: CGFloat = 14
        static let overlayCard: CGFloat = 18
    }

    enum Size {
        static let settingsRow: CGFloat = 44
        static let popoverRow: CGFloat = 48
        /// Overlay capsule/card width. Never changes between states.
        static let overlayWidth: CGFloat = 420
        static let orb: CGFloat = 34
    }
}
```

`Motion.swift`:

```swift
import SwiftUI

extension DS {
    /// Motion tokens (spec §3.4). Views must also honour
    /// `accessibilityReduceMotion`; these are the values for when motion is on.
    enum Motion {
        static let stateChange: Animation = .easeOut(duration: 0.18)
        static let orb: Animation = .spring(response: 0.35, dampingFraction: 0.7)
        static let pulseDuration: Double = 1.2
        static let breathDuration: Double = 1.6
        static let resultAutoDismiss: Double = 2.0
    }
}
```

- [ ] **Step 6: Run the tests — expect PASS**

```bash
xcodegen generate
xcodebuild -project SayVoice.xcodeproj -scheme SayVoice -derivedDataPath build test 2>&1 | grep -E "error:|Executed|failed" | tail -5
```

Expected: `Executed 7 tests, with 0 failures`.

- [ ] **Step 7: Commit**

```bash
git add SayVoice/DesignSystem Tests/SayVoiceTests/DesignTokensTests.swift SayVoice.xcodeproj
git commit -m "Add design system tokens: colours, typography, spacing, motion

Colour roles carry a dark and a light value and resolve per appearance;
values are plain numbers so tokens are Sendable globals. Typography uses
the bundled Onest and JetBrains Mono faces and falls back to the system
font silently if a face is missing."
```

---

### Task 3: Migrate yesterday's logic checks into real unit tests

**Files:**
- Test: `Tests/SayVoiceTests/HotkeyEventDecisionTests.swift`
- Test: `Tests/SayVoiceTests/SilenceTrimmerTests.swift`
- Test: `Tests/SayVoiceTests/VocabularyTests.swift`

**Interfaces:**
- Consumes (existing, unchanged): `HotkeyEventDecision.decide(isKeyDown:isAutorepeat:flags:required:wasDown:)`, `SilenceTrimmer.trim(_:) -> [Float]?`, `TagField.tokens(from:)`, `TagField.string(from:)`, `TranscriptionEngine.initialPrompt(vocabulary:)`, `TranscriptionEngine.punctuationHint`.

- [ ] **Step 1: Write the hotkey decision tests**

```swift
import CoreGraphics
import XCTest
@testable import SayVoice

/// The event tap consumes keyboard events system-wide. Getting this wrong
/// once made the letter "D" stop typing in every app, so the decision
/// function is pure and tested here.
final class HotkeyEventDecisionTests: XCTestCase {
    private let ctrlOptCmd = CGEventFlags([.maskControl, .maskAlternate, .maskCommand]).rawValue
    private let shift = CGEventFlags.maskShift.rawValue

    func testPlainLetterPassesThrough() {
        let down = HotkeyEventDecision.decide(isKeyDown: true, isAutorepeat: false, flags: 0, required: ctrlOptCmd, wasDown: false)
        XCTAssertFalse(down.consume); XCTAssertFalse(down.handle)
        let up = HotkeyEventDecision.decide(isKeyDown: false, isAutorepeat: false, flags: 0, required: ctrlOptCmd, wasDown: down.isDown)
        XCTAssertFalse(up.consume, "release of a plain letter must reach the system")
    }

    func testPlainAutorepeatPassesThrough() {
        let r = HotkeyEventDecision.decide(isKeyDown: true, isAutorepeat: true, flags: 0, required: ctrlOptCmd, wasDown: false)
        XCTAssertFalse(r.consume)
    }

    func testHotkeyPressIsConsumedAndHandled() {
        let d = HotkeyEventDecision.decide(isKeyDown: true, isAutorepeat: false, flags: ctrlOptCmd, required: ctrlOptCmd, wasDown: false)
        XCTAssertTrue(d.consume); XCTAssertTrue(d.handle); XCTAssertTrue(d.isDown)
    }

    func testHotkeyAutorepeatIsConsumedButNotHandled() {
        let r = HotkeyEventDecision.decide(isKeyDown: true, isAutorepeat: true, flags: ctrlOptCmd, required: ctrlOptCmd, wasDown: true)
        XCTAssertTrue(r.consume); XCTAssertFalse(r.handle)
    }

    func testReleaseIsHandledEvenIfModifiersAlreadyUp() {
        let up = HotkeyEventDecision.decide(isKeyDown: false, isAutorepeat: false, flags: 0, required: ctrlOptCmd, wasDown: true)
        XCTAssertTrue(up.consume); XCTAssertTrue(up.handle); XCTAssertFalse(up.isDown)
    }

    func testExtraModifierIsNotTheHotkey() {
        let d = HotkeyEventDecision.decide(isKeyDown: true, isAutorepeat: false, flags: ctrlOptCmd | shift, required: ctrlOptCmd, wasDown: false)
        XCTAssertFalse(d.consume)
    }
}
```

- [ ] **Step 2: Write the silence trimmer tests**

```swift
import XCTest
@testable import SayVoice

/// Whisper hallucinates on near-empty audio (it echoes the initial prompt),
/// so recordings without real speech must be rejected before transcription.
final class SilenceTrimmerTests: XCTestCase {
    private let rate = 16_000

    func testPureSilenceIsRejected() {
        XCTAssertNil(SilenceTrimmer.trim([Float](repeating: 0, count: rate * 7)))
    }

    func testQuietNoiseIsRejected() {
        var g = SystemRandomNumberGenerator()
        let noise = (0..<(rate * 7)).map { _ in Float.random(in: -0.002...0.002, using: &g) }
        XCTAssertNil(SilenceTrimmer.trim(noise))
    }

    func testSingleClickInSilenceIsRejected() {
        var s = [Float](repeating: 0, count: rate * 7)
        for i in rate..<(rate + 300) { s[i] = Float.random(in: -0.4...0.4) }   // ~19 ms click
        XCTAssertNil(SilenceTrimmer.trim(s), "one loud frame used to count as speech")
    }

    func testShortRealPhraseSurvives() {
        var s = [Float](repeating: 0, count: rate * 3)
        let start = rate / 2
        for i in start..<(start + Int(0.6 * Double(rate))) {
            s[i] = 0.08 * sin(Float(i) * 0.05) + Float.random(in: -0.02...0.02)
        }
        XCTAssertNotNil(SilenceTrimmer.trim(s), "0.6 s of speech must not be dropped")
    }

    func testTrimKeepsPaddingAroundSpeech() {
        var s = [Float](repeating: 0, count: rate * 4)
        for i in rate..<(rate * 2) { s[i] = 0.1 * sin(Float(i) * 0.03) }
        let t = SilenceTrimmer.trim(s)!
        XCTAssertLessThan(t.count, s.count)
        XCTAssertGreaterThan(t.count, rate)              // speech plus padding
        XCTAssertLessThan(t.count, rate + 2 * 8 * 480 + 480)  // not more than pad on each side
    }
}
```

- [ ] **Step 3: Write the vocabulary/prompt tests**

```swift
import XCTest
@testable import SayVoice

final class VocabularyTests: XCTestCase {

    func testTokensSplitOnCommaAndNewlineAndTrim() {
        XCTAssertEqual(TagField.tokens(from: "  API ,deployment,,\n frontend  "), ["API", "deployment", "frontend"])
    }

    func testStringRoundTripKeepsMultiWordTerms() {
        let s = "pull request, SwiftUI, Sentry"
        XCTAssertEqual(TagField.string(from: TagField.tokens(from: s)), s)
    }

    func testEmptyVocabularyYieldsOnlyThePunctuationHint() {
        XCTAssertEqual(TranscriptionEngine.initialPrompt(vocabulary: ""), TranscriptionEngine.punctuationHint)
        XCTAssertEqual(TranscriptionEngine.initialPrompt(vocabulary: nil), TranscriptionEngine.punctuationHint)
    }

    func testVocabularyIsWrappedInASentenceWithTheHintLast() {
        let p = TranscriptionEngine.initialPrompt(vocabulary: "API, Xcode")
        XCTAssertTrue(p.contains("API, Xcode."), "terms must end with a period so the model sees punctuated text")
        XCTAssertTrue(p.hasSuffix(TranscriptionEngine.punctuationHint), "hint goes last: whisper keeps the tail of an over-long prompt")
    }
}
```

- [ ] **Step 4: Run the tests — expect PASS**

```bash
xcodegen generate
xcodebuild -project SayVoice.xcodeproj -scheme SayVoice -derivedDataPath build test 2>&1 | grep -E "error:|Executed|failed" | tail -5
```

Expected: `Executed 22 tests, with 0 failures`. If a `SilenceTrimmer` test fails on `trim(_:)` visibility, the type is `enum SilenceTrimmer` with `static func trim` — internal, reachable via `@testable`.

- [ ] **Step 5: Commit**

```bash
git add Tests SayVoice.xcodeproj
git commit -m "Add unit tests for hotkey event decisions, silence guard and vocabulary prompt

These checks existed as throwaway scripts during the 2026-09-08 fixes;
they now run in the SayVoiceTests target."
```

---

### Task 4: Buttons, Chip, KeyCap

**Files:**
- Create: `SayVoice/DesignSystem/Components/Buttons.swift`
- Create: `SayVoice/DesignSystem/Components/Chip.swift`
- Create: `SayVoice/DesignSystem/Components/KeyCap.swift`
- Test: `Tests/SayVoiceTests/ComponentRenderTests.swift`

**Interfaces:**
- Produces: `.buttonStyle(.dsPrimary)`, `.dsSecondary`, `.dsLink`, `.dsDestructive`; `Chip(_ text: String, style: Chip.Style = .neutral)` with `Style { neutral, accent, ok, warn }`; `KeyCap(_ text: String)`.
- Test helper (used by later tasks): `func renderSize<V: View>(_ view: V, width: CGFloat?) -> CGSize` in `ComponentRenderTests`.

- [ ] **Step 1: Write the failing render tests**

```swift
import SwiftUI
import XCTest
@testable import SayVoice

/// Smoke tests: each component renders to a bitmap with a sane size in
/// both appearances. They catch layout that collapses to zero and code
/// paths that crash off-screen; they do not judge looks.
@MainActor
final class ComponentRenderTests: XCTestCase {

    func renderSize<V: View>(_ view: V, width: CGFloat? = nil, dark: Bool = true) -> CGSize {
        let host = NSHostingView(rootView: AnyView(view.fixedSize(horizontal: width == nil, vertical: true).frame(width: width)))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let size = host.fittingSize
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)
        XCTAssertNotNil(rep)
        if let rep { host.cacheDisplay(in: host.bounds, to: rep) }
        return size
    }

    func testChipRendersAllStyles() {
        for style in [Chip.Style.neutral, .accent, .ok, .warn] {
            for dark in [true, false] {
                let s = renderSize(Chip("recommended", style: style), dark: dark)
                XCTAssertGreaterThan(s.width, 40); XCTAssertGreaterThan(s.height, 16); XCTAssertLessThan(s.height, 30)
            }
        }
    }

    func testKeyCapRenders() {
        let s = renderSize(KeyCap("⌃⌥⌘D"))
        XCTAssertGreaterThan(s.width, 40); XCTAssertGreaterThan(s.height, 20)
    }

    func testButtonStylesRender() {
        XCTAssertGreaterThan(renderSize(Button("Download") {}.buttonStyle(.dsPrimary)).height, 24)
        XCTAssertGreaterThan(renderSize(Button("Stop") {}.buttonStyle(.dsSecondary)).height, 24)
        XCTAssertGreaterThan(renderSize(Button("Copy") {}.buttonStyle(.dsLink)).height, 14)
        XCTAssertGreaterThan(renderSize(Button("Clear…") {}.buttonStyle(.dsDestructive)).height, 14)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodegen generate
xcodebuild -project SayVoice.xcodeproj -scheme SayVoice -derivedDataPath build test 2>&1 | grep -E "error:" | head -3
```

Expected: `cannot find 'Chip' in scope` (and `KeyCap`, `dsPrimary`).

- [ ] **Step 3: Create `Buttons.swift`**

```swift
import SwiftUI

/// Button styles in token colours. Pressed state dims; disabled state fades.
/// Primary is the only style that uses the accent — one per screen.
struct DSPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.font(.bodyMedium))
            .foregroundStyle(.white)
            .padding(.horizontal, DS.Space.s16)
            .padding(.vertical, DS.Space.s8)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                    .fill(DS.Colors.accent.color)
            )
            .opacity(configuration.isPressed ? 0.85 : (isEnabled ? 1 : 0.45))
            .animation(DS.Motion.stateChange, value: configuration.isPressed)
    }
}

struct DSSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.font(.bodyMedium))
            .foregroundStyle(DS.Colors.text.color)
            .padding(.horizontal, DS.Space.s12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.control + 2, style: .continuous)
                    .fill(DS.Colors.surface2.color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.control + 2, style: .continuous)
                    .strokeBorder(DS.Colors.line.color, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : (isEnabled ? 1 : 0.45))
            .animation(DS.Motion.stateChange, value: configuration.isPressed)
    }
}

struct DSLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.font(.bodyMedium))
            .foregroundStyle(DS.Colors.accent.color)
            .padding(.vertical, 4)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct DSDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.font(.bodyMedium))
            .foregroundStyle(DS.Colors.rec.color)
            .padding(.vertical, 4)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == DSPrimaryButtonStyle {
    static var dsPrimary: DSPrimaryButtonStyle { .init() }
}
extension ButtonStyle where Self == DSSecondaryButtonStyle {
    static var dsSecondary: DSSecondaryButtonStyle { .init() }
}
extension ButtonStyle where Self == DSLinkButtonStyle {
    static var dsLink: DSLinkButtonStyle { .init() }
}
extension ButtonStyle where Self == DSDestructiveButtonStyle {
    static var dsDestructive: DSDestructiveButtonStyle { .init() }
}
```

- [ ] **Step 4: Create `Chip.swift`**

```swift
import SwiftUI

/// Small capsule label: "recommended", "574 MB", "downloaded".
/// Neutral by default; `.accent` is reserved for the recommended model.
struct Chip: View {
    enum Style { case neutral, accent, ok, warn }

    let text: String
    var style: Style = .neutral

    init(_ text: String, style: Style = .neutral) {
        self.text = text
        self.style = style
    }

    var body: some View {
        Text(text)
            .font(DS.font(.valueSmall))
            .foregroundStyle(foreground)
            .padding(.horizontal, DS.Space.s8)
            .padding(.vertical, 3)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(border, lineWidth: 1))
    }

    private var foreground: Color {
        switch style {
        case .neutral: return DS.Colors.muted.color
        case .accent:  return DS.Colors.accent.color
        case .ok:      return DS.Colors.ok.color
        case .warn:    return DS.Colors.warn.color
        }
    }

    private var fill: Color {
        switch style {
        case .neutral: return DS.Colors.surface2.color
        case .accent:  return DS.Colors.accentSoft.color
        case .ok:      return DS.Colors.ok.color.opacity(0.12)
        case .warn:    return DS.Colors.warn.color.opacity(0.14)
        }
    }

    private var border: Color {
        switch style {
        case .neutral: return DS.Colors.line.color
        case .accent:  return DS.Colors.accent.color.opacity(0.35)
        case .ok:      return DS.Colors.ok.color.opacity(0.3)
        case .warn:    return DS.Colors.warn.color.opacity(0.3)
        }
    }
}
```

- [ ] **Step 5: Create `KeyCap.swift`**

```swift
import SwiftUI

/// Hotkey display in monospace on an inset cap: ⌃⌥⌘D, Right ⌥, F13.
struct KeyCap: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(DS.font(.value))
            .foregroundStyle(DS.Colors.text.color)
            .padding(.horizontal, DS.Space.s12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .fill(DS.Colors.surface2.color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .strokeBorder(DS.Colors.line.color, lineWidth: 1)
            )
    }
}
```

- [ ] **Step 6: Run the tests — expect PASS**

```bash
xcodegen generate
xcodebuild -project SayVoice.xcodeproj -scheme SayVoice -derivedDataPath build test 2>&1 | grep -E "error:|Executed|failed" | tail -5
```

Expected: `Executed 25 tests, with 0 failures`.

- [ ] **Step 7: Commit**

```bash
git add SayVoice/DesignSystem/Components Tests/SayVoiceTests/ComponentRenderTests.swift SayVoice.xcodeproj
git commit -m "Add button styles, Chip and KeyCap components"
```

---

### Task 5: Orb

**Files:**
- Create: `SayVoice/DesignSystem/Components/Orb.swift`
- Test: append to `Tests/SayVoiceTests/ComponentRenderTests.swift`

**Interfaces:**
- Produces: `struct Orb: View { enum State: Equatable { idle, recording, transcribing, done, error }; init(state: State, size: CGFloat = DS.Size.orb) }`.

- [ ] **Step 1: Add the failing test**

Append inside `ComponentRenderTests`:

```swift
    func testOrbRendersEveryState() {
        for state in [Orb.State.idle, .recording, .transcribing, .done, .error] {
            let s = renderSize(Orb(state: state))
            XCTAssertEqual(s.width, DS.Size.orb + 10, accuracy: 0.5, "orb frame includes the 5pt halo ring")
            XCTAssertEqual(s.height, DS.Size.orb + 10, accuracy: 0.5)
        }
    }
```

- [ ] **Step 2: Run to verify it fails** — `cannot find 'Orb' in scope`.

- [ ] **Step 3: Create `Orb.swift`**

```swift
import SwiftUI

/// The single state indicator of the app. It appears in the overlay, in the
/// history popover header and (rendered to an image) in the menu bar.
///
/// Recording pulses, transcribing breathes; both stop under Reduce Motion
/// and are replaced by a steady colour.
struct Orb: View {
    enum State: Equatable { case idle, recording, transcribing, done, error }

    let state: State
    var size: CGFloat = DS.Size.orb

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SwiftUI.State private var phase = false

    /// Halo ring width around the orb; part of the frame so layout is stable.
    private let halo: CGFloat = 5

    init(state: State, size: CGFloat = DS.Size.orb) {
        self.state = state
        self.size = size
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(haloColor)
                .frame(width: size + halo * 2, height: size + halo * 2)
                .scaleEffect(pulseScale)
                .opacity(pulseOpacity)

            Circle()
                .fill(gradient)
                .frame(width: size, height: size)
                .scaleEffect(breathScale)

            glyph
        }
        .frame(width: size + halo * 2, height: size + halo * 2)
        .animation(DS.Motion.orb, value: state)
        .onAppear(perform: startMotion)
        .onChange(of: state) { _, _ in startMotion() }
        .accessibilityLabel(label)
    }

    // MARK: - Looks

    private var gradient: RadialGradient {
        let (top, base): (Color, Color)
        switch state {
        case .idle, .transcribing: (top, base) = (DS.Colors.accent2.color, DS.Colors.accent.color)
        case .recording:           (top, base) = (Color(red: 1, green: 0.54, blue: 0.54), DS.Colors.rec.color)
        case .done:                (top, base) = (Color(red: 0.55, green: 0.93, blue: 0.72), DS.Colors.ok.color)
        case .error:               (top, base) = (Color(red: 0.97, green: 0.78, blue: 0.45), DS.Colors.warn.color)
        }
        return RadialGradient(colors: [top, base], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size)
    }

    private var haloColor: Color {
        switch state {
        case .idle, .transcribing: return DS.Colors.accentSoft.color
        case .recording:           return DS.Colors.rec.color.opacity(0.25)
        case .done:                return DS.Colors.ok.color.opacity(0.22)
        case .error:               return DS.Colors.warn.color.opacity(0.22)
        }
    }

    @ViewBuilder private var glyph: some View {
        switch state {
        case .done:
            Image(systemName: "checkmark").font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(.white)
        case .error:
            Image(systemName: "exclamationmark").font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(.white)
        case .recording:
            Circle().fill(.white).frame(width: size * 0.3, height: size * 0.3)
        case .idle, .transcribing:
            EmptyView()
        }
    }

    private var label: String {
        switch state {
        case .idle: return "Ready"
        case .recording: return "Recording"
        case .transcribing: return "Transcribing"
        case .done: return "Done"
        case .error: return "Error"
        }
    }

    // MARK: - Motion

    private var pulseScale: CGFloat {
        guard state == .recording, !reduceMotion else { return 1 }
        return phase ? 1.35 : 1.0
    }

    private var pulseOpacity: Double {
        guard state == .recording, !reduceMotion else { return 1 }
        return phase ? 0.0 : 1.0
    }

    private var breathScale: CGFloat {
        guard state == .transcribing, !reduceMotion else { return 1 }
        return phase ? 1.06 : 0.96
    }

    private func startMotion() {
        phase = false
        guard !reduceMotion else { return }
        switch state {
        case .recording:
            withAnimation(.easeOut(duration: DS.Motion.pulseDuration).repeatForever(autoreverses: false)) { phase = true }
        case .transcribing:
            withAnimation(.easeInOut(duration: DS.Motion.breathDuration / 2).repeatForever(autoreverses: true)) { phase = true }
        case .idle, .done, .error:
            break
        }
    }
}
```

- [ ] **Step 4: Run the tests — expect PASS** (`Executed 26 tests`).

- [ ] **Step 5: Commit**

```bash
git add SayVoice/DesignSystem/Components/Orb.swift Tests SayVoice.xcodeproj
git commit -m "Add Orb state indicator with pulse and breath motion"
```

---

### Task 6: GlassPanel, Card, SettingsRow

**Files:**
- Create: `SayVoice/DesignSystem/Components/GlassPanel.swift`
- Create: `SayVoice/DesignSystem/Components/Card.swift`
- Create: `SayVoice/DesignSystem/Components/SettingsRow.swift`
- Test: append to `Tests/SayVoiceTests/ComponentRenderTests.swift`

**Interfaces:**
- Produces:
  - `struct GlassPanel<Content: View>: View { enum Shape { capsule, card }; init(shape: Shape, @ViewBuilder content: () -> Content) }`
  - `struct Card<Content: View>: View { init(title: String? = nil, subtitle: String? = nil, @ViewBuilder content: () -> Content) }`
  - `struct SettingsRow<Control: View>: View { init(_ label: String, note: String? = nil, @ViewBuilder control: () -> Control) }`

- [ ] **Step 1: Add the failing tests**

```swift
    func testGlassPanelRendersBothShapes() {
        for shape in [GlassPanel<Text>.Shape.capsule, .card] {
            let s = renderSize(GlassPanel(shape: shape) { Text("Listening") })
            XCTAssertEqual(s.width, DS.Size.overlayWidth, accuracy: 0.5)
            XCTAssertGreaterThan(s.height, 30)
        }
    }

    func testCardAndRowRender() {
        let s = renderSize(
            Card(title: "Recording hotkey", subtitle: "Key, combination or mouse button") {
                SettingsRow("Show overlay", note: "Glass capsule at the bottom of the screen") { Toggle("", isOn: .constant(true)).labelsHidden() }
                SettingsRow("Sound feedback") { Toggle("", isOn: .constant(false)).labelsHidden() }
            },
            width: 600
        )
        XCTAssertEqual(s.width, 600, accuracy: 0.5)
        XCTAssertGreaterThan(s.height, 2 * DS.Size.settingsRow)
    }
```

- [ ] **Step 2: Run to verify they fail** — `cannot find 'GlassPanel'`.

- [ ] **Step 3: Create `GlassPanel.swift`**

```swift
import SwiftUI

/// Liquid Glass container for the overlay. Tint, border and top highlight
/// come from tokens; the accent appears here only as the border (one of the
/// three places the accent is allowed).
struct GlassPanel<Content: View>: View {
    enum Shape { case capsule, card }

    let shape: Shape
    @ViewBuilder let content: () -> Content

    init(shape: Shape, @ViewBuilder content: @escaping () -> Content) {
        self.shape = shape
        self.content = content
    }

    var body: some View {
        content()
            .padding(.horizontal, shape == .capsule ? DS.Space.s16 : DS.Space.s20)
            .padding(.vertical, shape == .capsule ? DS.Space.s12 : DS.Space.s16)
            .frame(width: DS.Size.overlayWidth, alignment: .leading)
            .glassEffect(.regular.tint(DS.Colors.accent.color.opacity(0.10)), in: clipShape)
            .overlay(clipShape.strokeBorder(DS.Colors.glassLine.color, lineWidth: 1))
            .overlay(alignment: .top) {
                // 1px specular line along the top edge
                clipShape
                    .strokeBorder(
                        LinearGradient(colors: [DS.Colors.glassHighlight.color, .clear], startPoint: .top, endPoint: .center),
                        lineWidth: 1
                    )
                    .mask(Rectangle().frame(height: 2), alignment: .top)
            }
            .shadow(color: DS.Colors.glassShadow.color, radius: 25, x: 0, y: 20)
    }

    private var clipShape: AnyInsettableShape {
        switch shape {
        case .capsule: return AnyInsettableShape(Capsule(style: .continuous))
        case .card:    return AnyInsettableShape(RoundedRectangle(cornerRadius: DS.Radius.overlayCard, style: .continuous))
        }
    }
}

/// Type-erased insettable shape so one `overlay` chain serves both variants.
struct AnyInsettableShape: InsettableShape {
    private let _path: @Sendable (CGRect) -> Path
    private let _inset: @Sendable (CGFloat) -> AnyInsettableShape

    init<S: InsettableShape>(_ shape: S) {
        _path = { shape.path(in: $0) }
        _inset = { AnyInsettableShape(shape.inset(by: $0)) }
    }

    func path(in rect: CGRect) -> Path { _path(rect) }
    func inset(by amount: CGFloat) -> AnyInsettableShape { _inset(amount) }
}
```

- [ ] **Step 4: Create `Card.swift`**

```swift
import SwiftUI

/// Settings card: optional title/subtitle header, then rows separated by hairlines.
struct Card<Content: View>: View {
    let title: String?
    let subtitle: String?
    @ViewBuilder let content: () -> Content

    init(title: String? = nil, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let title { Text(title).font(DS.font(.title)).foregroundStyle(DS.Colors.text.color) }
                    if let subtitle { Text(subtitle).font(DS.font(.caption)).foregroundStyle(DS.Colors.muted.color) }
                }
                .padding(.horizontal, DS.Space.s16)
                .padding(.top, DS.Space.s16)
                .padding(.bottom, DS.Space.s8)
            }
            content()
        }
        .padding(.bottom, DS.Space.s8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).fill(DS.Colors.surface.color))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).strokeBorder(DS.Colors.line.color, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
    }
}
```

- [ ] **Step 5: Create `SettingsRow.swift`**

```swift
import SwiftUI

/// One settings line: label (and optional note) on the left, control on the
/// right, 44pt tall, hairline on top. Notes are `caption`/`muted` — the only
/// place explanatory text is allowed inside a card.
struct SettingsRow<Control: View>: View {
    let label: String
    let note: String?
    @ViewBuilder let control: () -> Control

    init(_ label: String, note: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.label = label
        self.note = note
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.s12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(DS.font(.bodyMedium)).foregroundStyle(DS.Colors.text.color)
                if let note { Text(note).font(DS.font(.caption)).foregroundStyle(DS.Colors.muted.color) }
            }
            Spacer(minLength: DS.Space.s12)
            control()
        }
        .padding(.horizontal, DS.Space.s16)
        .frame(minHeight: DS.Size.settingsRow)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.Colors.line.color).frame(height: 1).padding(.leading, DS.Space.s16)
        }
    }
}
```

- [ ] **Step 6: Run the tests — expect PASS** (`Executed 28 tests`). If `glassEffect` fails to compile, confirm the SDK is macOS 26 (`xcodebuild -showsdks`), the existing `UI/OverlayView.swift` uses the same modifier.

- [ ] **Step 7: Commit**

```bash
git add SayVoice/DesignSystem/Components Tests SayVoice.xcodeproj
git commit -m "Add GlassPanel, Card and SettingsRow components"
```

---

### Task 7: Waveform with BarEngine (moved from the old overlay)

**Files:**
- Create: `SayVoice/DesignSystem/Components/Waveform.swift`
- Test: `Tests/SayVoiceTests/BarEngineTests.swift`

**Interfaces:**
- Consumes: nothing from the old file at runtime; the `BarEngine` code is copied verbatim from `SayVoice/UI/OverlayView.swift` (the old file is deleted in Task 9).
- Produces: `struct Waveform: View { init(levels: [Float], bars: Int = 24, tint: Color) }`; `final class BarEngine { private(set) var heights: [CGFloat]; func step(now: TimeInterval, history: [Float], barCount: Int) }`.

- [ ] **Step 1: Write the failing engine tests**

```swift
import XCTest
@testable import SayVoice

/// BarEngine smooths raw levels into bar heights: fast attack, slow decay,
/// with a small per-bar delay so the wave "ripples" from the centre.
final class BarEngineTests: XCTestCase {

    func testBarsRiseQuicklyOnLoudInput() {
        let e = BarEngine()
        var t: TimeInterval = 0
        let loud = [Float](repeating: 0.9, count: 64)
        for _ in 0..<6 { t += 1.0 / 60; e.step(now: t, history: loud, barCount: 24) }   // 100 ms
        XCTAssertGreaterThan(e.heights[12], 0.5, "centre bar should be well up after 100 ms of loud input")
    }

    func testBarsDecaySlowlyOnSilence() {
        let e = BarEngine()
        var t: TimeInterval = 0
        let loud = [Float](repeating: 0.9, count: 64)
        for _ in 0..<30 { t += 1.0 / 60; e.step(now: t, history: loud, barCount: 24) }
        let peak = e.heights[12]
        let quiet = [Float](repeating: 0, count: 64)
        for _ in 0..<3 { t += 1.0 / 60; e.step(now: t, history: quiet, barCount: 24) }   // 50 ms
        XCTAssertGreaterThan(e.heights[12], peak * 0.4, "decay must be visibly slower than attack")
        for _ in 0..<60 { t += 1.0 / 60; e.step(now: t, history: quiet, barCount: 24) }  // +1 s
        XCTAssertLessThan(e.heights[12], 0.05)
    }

    func testBarCountChangeResets() {
        let e = BarEngine()
        e.step(now: 1, history: [0.5], barCount: 8)
        XCTAssertEqual(e.heights.count, 8)
        e.step(now: 2, history: [0.5], barCount: 24)
        XCTAssertEqual(e.heights.count, 24)
    }
}
```

- [ ] **Step 2: Run to verify it fails** — `cannot find 'BarEngine'`.

- [ ] **Step 3: Create `Waveform.swift`**

```swift
import SwiftUI

/// Live level bars, mirrored below a centre line. Bars stay in place and move
/// up and down; each bar has its own character (sensitivity and wobble), a
/// fast rise and a slow fall, and the level ripples from the centre outwards.
/// One `Canvas`, one draw pass per frame.
struct Waveform: View {
    let levels: [Float]
    var bars: Int = 24
    var tint: Color

    @State private var engine = BarEngine()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let spacing: CGFloat = 3

    init(levels: [Float], bars: Int = 24, tint: Color) {
        self.levels = levels
        self.bars = bars
        self.tint = tint
    }

    var body: some View {
        TimelineView(reduceMotion ? .periodic(from: .now, by: 1.0 / 15) : .animation) { timeline in
            Canvas { ctx, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                engine.step(now: now, history: levels, barCount: bars)

                let slot = size.width / CGFloat(bars)
                let barWidth = max(2, slot - spacing)
                let axisY = size.height / 2
                let maxHalf = axisY - 2

                var reflection = ctx
                reflection.opacity = 0.32

                for k in 0..<bars {
                    let h = min(maxHalf, max(2, engine.heights[k] * maxHalf))
                    let x = CGFloat(k) * slot + spacing / 2
                    let radius = min(barWidth / 2, h / 2)

                    ctx.fill(
                        Path(roundedRect: CGRect(x: x, y: axisY - h, width: barWidth, height: h), cornerRadius: radius),
                        with: .color(tint)
                    )
                    let mh = h * 0.55
                    reflection.fill(
                        Path(roundedRect: CGRect(x: x, y: axisY + 2, width: barWidth, height: mh), cornerRadius: min(radius, mh / 2)),
                        with: .color(tint)
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Per-bar heights with attack/decay smoothing. A plain class on purpose:
/// the Canvas is redrawn by TimelineView, and mutations during drawing must
/// not invalidate the view.
final class BarEngine {
    private(set) var heights: [CGFloat] = []
    private var lastTime: TimeInterval = 0

    /// Deterministic per-bar "character" (pseudo-random hash).
    private static func hash(_ k: Int) -> CGFloat {
        let s = sin(CGFloat(k) * 12.9898) * 43758.5453
        return s - s.rounded(.down)
    }

    func step(now: TimeInterval, history: [Float], barCount: Int) {
        if heights.count != barCount {
            heights = Array(repeating: 0, count: barCount)
            lastTime = now
        }
        let dt = min(0.1, max(0.001, now - lastTime))
        lastTime = now

        let center = CGFloat(barCount - 1) / 2

        for k in 0..<barCount {
            let hashK = Self.hash(k)
            let distance = abs(CGFloat(k) - center)

            // Ripple: outer bars react with a small delay (~40 Hz history)
            let delay = Int(distance * 0.9)
            let idx = history.count - 1 - delay
            let raw: CGFloat = (idx >= 0 && idx < history.count) ? CGFloat(history[idx]) : 0

            // Individuality: sensitivity plus a private wobble whose amplitude grows with volume
            let sensitivity = 0.7 + 0.3 * hashK
            let wobble = 0.72 + 0.28 * sin(now * (2.6 + 3.2 * Double(hashK)) + Double(k) * 1.7)
            let level = pow(min(1, raw), 1.15)
            let target = min(1, level * sensitivity * wobble * 1.5)

            // Fast rise, slow fall — classic VU dynamics
            let rate: CGFloat = target > heights[k] ? 24 : 9
            let alpha = 1 - exp(-dt * rate)
            heights[k] += (target - heights[k]) * alpha
        }
    }
}
```

- [ ] **Step 4: Run the tests — expect PASS** (`Executed 31 tests`). If `testBarsRiseQuicklyOnLoudInput` fails, print `e.heights[12]` — the attack rate 24/s gives ≈0.9 after 100 ms; a value near 0 means `history` indexing returned 0 (check the `delay` math with a 64-sample history).

- [ ] **Step 5: Commit**

```bash
git add SayVoice/DesignSystem/Components/Waveform.swift Tests/SayVoiceTests/BarEngineTests.swift SayVoice.xcodeproj
git commit -m "Add Waveform component; move BarEngine out of the overlay with tests"
```

---

### Task 8: Overlay model and window controller move to Features/Overlay

**Files:**
- Move: `SayVoice/UI/OverlayModel.swift` → `SayVoice/Features/Overlay/OverlayModel.swift` (rewritten in English)
- Move: `SayVoice/UI/OverlayWindowController.swift` → `SayVoice/Features/Overlay/OverlayWindowController.swift` (rewritten in English; behaviour preserved, plus hover-aware dismiss and result/error mouse handling)

**Interfaces:**
- Consumes: `OverlayView(model:)` (Task 9 provides the new one; until then the old `UI/OverlayView.swift` still compiles against the same `OverlayModel` API — the added properties are additive).
- Produces (used by Task 10 / `AppCoordinator`):
  - `OverlayModel`: `displayState`, `message`, `recordingStart`, `isToggleMode`, `hotkeyName`, `onStop`, **new** `durationSeconds: Double`, `onCopy: (@MainActor () -> Void)?`, `onShowAll: (@MainActor () -> Void)?`, `errorAction: (title: String, handler: @MainActor () -> Void)?`, `isHovered: Bool`, `levelHistory`, `appendLevel`, `resetLevels`.
  - `OverlayWindowController`: `showRecording(isToggleMode:hotkeyName:onStop:)`, `showTranscribing()`, **changed** `showResult(text:durationSeconds:onCopy:onShowAll:)`, **changed** `showError(message:action:)`, `updateAudioLevel(_:)`, `dismiss(after:)`, `static let panelSize`.

- [ ] **Step 1: Create `Features/Overlay/OverlayModel.swift`**

```swift
import Foundation

/// State of the recording overlay. Owned by `OverlayWindowController`,
/// observed by `OverlayView`.
@MainActor @Observable
final class OverlayModel {
    enum DisplayState: Equatable {
        case hidden
        case recording
        case transcribing
        case result
        case error
    }

    var displayState: DisplayState = .hidden
    var message: String = ""
    var audioLevel: Float = 0
    var recordingStart: Date = Date()

    /// Toggle mode: the recording does not stop on key release, so the
    /// overlay shows a Stop button and a hint.
    var isToggleMode: Bool = false
    /// Display name of the configured hotkey, for the hint text.
    var hotkeyName: String = ""
    var onStop: (@MainActor () -> Void)?

    /// Result state: length of the recording and the two actions.
    var durationSeconds: Double = 0
    var onCopy: (@MainActor () -> Void)?
    var onShowAll: (@MainActor () -> Void)?

    /// Error state: optional action such as "Open System Settings".
    var errorAction: (title: String, handler: @MainActor () -> Void)?

    /// Pointer is over the panel — auto-dismiss waits while this is true.
    var isHovered: Bool = false

    /// Recent levels (~40 Hz, newest last) — the waveform reads them with a
    /// per-bar delay so the wave ripples from the centre.
    private(set) var levelHistory: [Float] = []

    private static let historyLimit = 64

    func appendLevel(_ level: Float) {
        audioLevel = level
        levelHistory.append(level)
        if levelHistory.count > Self.historyLimit {
            levelHistory.removeFirst(levelHistory.count - Self.historyLimit)
        }
    }

    func resetLevels() {
        levelHistory = []
        audioLevel = 0
    }
}
```

- [ ] **Step 2: Create `Features/Overlay/OverlayWindowController.swift`**

```swift
import AppKit
import SwiftUI

/// Floating, non-activating panel that hosts the overlay. Positioning and
/// focus rules were tuned on 2026-09-08 and are kept exactly:
/// fixed panel size restored on every show, centred on the screen under the
/// pointer, never key, mouse-transparent unless the content has controls.
@MainActor
final class OverlayWindowController: NSWindowController {
    let model = OverlayModel()
    private var dismissTask: Task<Void, Never>?
    /// Incremented on every show — a stale dismiss completion must not hide
    /// a panel that was shown again meanwhile.
    private var showGeneration = 0

    /// Fixed panel size. The content is centred inside; the margin exists so
    /// the glass shadow is not clipped by the window edge.
    static let panelSize = NSSize(width: 640, height: 280)

    init() {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.isMovableByWindowBackground = false
        // Never take focus: .nonactivatingPanel keeps the app inactive on click,
        // becomesKeyOnlyIfNeeded keeps the panel non-key for plain buttons.
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.hasShadow = false
        // Mouse-transparent by default: the panel floats over other apps and
        // must not swallow clicks. Enabled only for states with controls.
        panel.ignoresMouseEvents = true

        super.init(window: panel)

        let hosting = NSHostingView(rootView: OverlayView(model: model))
        hosting.sizingOptions = []
        hosting.frame = panel.contentView!.bounds
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        positionPanel()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Public API

    func showRecording(isToggleMode: Bool = false, hotkeyName: String = "", onStop: (@MainActor () -> Void)? = nil) {
        cancelDismiss()
        model.displayState = .recording
        model.isToggleMode = isToggleMode
        model.hotkeyName = hotkeyName
        model.onStop = onStop
        model.resetLevels()
        model.recordingStart = Date()
        window?.ignoresMouseEvents = !isToggleMode   // Stop button needs clicks
        showPanel()
    }

    func showTranscribing() {
        cancelDismiss()
        model.displayState = .transcribing
        model.resetLevels()
        window?.ignoresMouseEvents = true
        showPanel()
    }

    func showResult(
        text: String,
        durationSeconds: Double,
        onCopy: (@MainActor () -> Void)?,
        onShowAll: (@MainActor () -> Void)?
    ) {
        cancelDismiss()
        model.displayState = .result
        model.message = text
        model.durationSeconds = durationSeconds
        model.onCopy = onCopy
        model.onShowAll = onShowAll
        window?.ignoresMouseEvents = false          // Copy / Show all + hover
        showPanel()
    }

    func showError(message: String, action: (title: String, handler: @MainActor () -> Void)? = nil) {
        cancelDismiss()
        model.displayState = .error
        model.message = message
        model.errorAction = action
        window?.ignoresMouseEvents = action == nil
        showPanel()
    }

    func updateAudioLevel(_ level: Float) {
        model.appendLevel(level)
    }

    /// Hides the panel after `delay`. While the pointer is over the panel the
    /// countdown pauses, so the user can read a long result or click Copy.
    func dismiss(after delay: TimeInterval = 0) {
        cancelDismiss()
        guard delay > 0 else { animateDismiss(); return }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            while let self, self.model.isHovered, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard !Task.isCancelled else { return }
            self?.animateDismiss()
        }
    }

    // MARK: - Private

    private func cancelDismiss() {
        dismissTask?.cancel()
        dismissTask = nil
    }

    private func showPanel() {
        showGeneration += 1
        positionPanel()
        guard window?.isVisible != true else {
            window?.animator().alphaValue = 1.0     // may be mid fade-out
            return
        }
        window?.alphaValue = 0
        window?.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            window?.animator().alphaValue = 1.0
        }
    }

    private func animateDismiss() {
        let generation = showGeneration
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            self.window?.animator().alphaValue = 0.0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.showGeneration == generation else { return }
                self.window?.orderOut(nil)
                self.window?.ignoresMouseEvents = true
                self.model.isHovered = false
                // Empty the view tree: a hidden panel with live animations
                // keeps rendering at 60 fps.
                self.model.displayState = .hidden
            }
        }
    }

    /// Screen the user is working on. `NSScreen.main` is unreliable for a
    /// background app with several displays; the pointer position is a
    /// dependable signal — people dictate where the caret and the mouse are.
    private func targetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func positionPanel() {
        guard let window, let screen = targetScreen() else { return }
        let frame = screen.frame
        let visibleFrame = screen.visibleFrame
        // Size comes from the constant, never from window.frame: in .hidden the
        // view tree is empty and the window can collapse; centring on that
        // size pushed the panel right by half its width.
        let size = Self.panelSize

        // X on the physical screen centre (visibleFrame shifts with a side Dock),
        // Y in the visible frame so the panel never sits under the Dock:
        // lower third, above chat input fields.
        var origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: visibleFrame.minY + visibleFrame.height * 0.22
        )
        origin.x = min(max(origin.x, visibleFrame.minX), max(visibleFrame.minX, visibleFrame.maxX - size.width))
        origin.y = min(max(origin.y, visibleFrame.minY), max(visibleFrame.minY, visibleFrame.maxY - size.height))

        window.setFrame(NSRect(origin: origin, size: size), display: false)
    }
}
```

- [ ] **Step 3: Delete the old files and make the old view compile against the new model**

```bash
git rm -q SayVoice/UI/OverlayModel.swift SayVoice/UI/OverlayWindowController.swift
```

The old `SayVoice/UI/OverlayView.swift` still references `model.displayState`, `model.isToggleMode`, `model.hotkeyName`, `model.onStop`, `model.recordingStart`, `model.levelHistory` — all still present, so it compiles. `AppCoordinator` calls `showResult(text:)` and `showError(message:)` — those signatures changed. Temporarily update the two call sites in `SayVoice/App/AppCoordinator.swift` (they get their final form in Task 10):

```swift
                    overlayController?.showResult(text: text, durationSeconds: durationSec, onCopy: nil, onShowAll: nil)
```

and

```swift
                    overlayController?.showError(message: msg)
```

(the second is unchanged in shape because `action` defaults to `nil`).

- [ ] **Step 4: Generate, build, run tests — expect BUILD SUCCEEDED and all tests passing**

```bash
xcodegen generate
xcodebuild -project SayVoice.xcodeproj -scheme SayVoice -configuration Release -derivedDataPath build build 2>&1 | grep -E "error:|BUILD"
xcodebuild -project SayVoice.xcodeproj -scheme SayVoice -derivedDataPath build test 2>&1 | grep -E "Executed|failed" | tail -2
```

- [ ] **Step 5: Commit**

```bash
git add -A SayVoice/Features/Overlay SayVoice/UI SayVoice/App/AppCoordinator.swift SayVoice.xcodeproj
git commit -m "Move overlay model and window controller to Features/Overlay

Rewritten in English with behaviour preserved. Result and error states
now carry actions, and auto-dismiss pauses while the pointer is over the
panel."
```

---

### Task 9: New OverlayView with four state contents

**Files:**
- Delete: `SayVoice/UI/OverlayView.swift`
- Create: `SayVoice/Features/Overlay/OverlayView.swift`
- Create: `SayVoice/Features/Overlay/RecordingContent.swift`
- Create: `SayVoice/Features/Overlay/TranscribingContent.swift`
- Create: `SayVoice/Features/Overlay/ResultContent.swift`
- Create: `SayVoice/Features/Overlay/ErrorContent.swift`
- Test: `Tests/SayVoiceTests/OverlayRenderTests.swift`

**Interfaces:**
- Consumes: `OverlayModel` (Task 8), `GlassPanel`, `Orb`, `Waveform`, `Chip`, button styles, `DS` tokens.
- Produces: `struct OverlayView: View { init(model: OverlayModel) }`.

- [ ] **Step 1: Write the failing render test**

```swift
import SwiftUI
import XCTest
@testable import SayVoice

@MainActor
final class OverlayRenderTests: XCTestCase {

    private func render(_ model: OverlayModel) -> CGSize {
        let host = NSHostingView(rootView: OverlayView(model: model)
            .frame(width: OverlayWindowController.panelSize.width, height: OverlayWindowController.panelSize.height))
        host.frame = CGRect(origin: .zero, size: OverlayWindowController.panelSize)
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        return host.fittingSize
    }

    func testHiddenStateKeepsPanelSize() {
        let m = OverlayModel()
        m.displayState = .hidden
        let s = render(m)
        XCTAssertEqual(s.width, OverlayWindowController.panelSize.width, accuracy: 0.5,
                       "the Color.clear backing must keep the window from collapsing")
    }

    func testEveryStateRenders() {
        for state in [OverlayModel.DisplayState.recording, .transcribing, .result, .error] {
            let m = OverlayModel()
            m.displayState = state
            m.message = "Let's discuss the sync module architecture; the client polls the server every thirty seconds."
            m.isToggleMode = true
            m.hotkeyName = "⌃⌥⌘D"
            m.durationSeconds = 12.4
            m.errorAction = ("Open System Settings", {})
            _ = render(m)
        }
    }
}
```

- [ ] **Step 2: Delete the old view and create the new root**

```bash
git rm -q SayVoice/UI/OverlayView.swift
```

`Features/Overlay/OverlayView.swift`:

```swift
import SwiftUI

/// Root of the overlay. One glass panel of fixed width; the state decides
/// whether it is a capsule (recording, transcribing) or a card (result,
/// error) and what goes inside. Width never changes between states.
struct OverlayView: View {
    let model: OverlayModel

    var body: some View {
        ZStack {
            // Transparent backing the size of the panel. Without it the hosting
            // view collapses in .hidden, the window shrinks around it, and the
            // next show is centred on the collapsed size. Color.clear draws
            // nothing and does not wake the render loop.
            Color.clear

            if model.displayState != .hidden {
                GlassPanel(shape: isCard ? .card : .capsule) {
                    content
                }
                .onHover { model.isHovered = $0 }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(DS.Motion.stateChange, value: model.displayState)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isCard: Bool {
        model.displayState == .result || model.displayState == .error
    }

    @ViewBuilder private var content: some View {
        switch model.displayState {
        case .hidden:       EmptyView()
        case .recording:    RecordingContent(model: model)
        case .transcribing: TranscribingContent()
        case .result:       ResultContent(model: model)
        case .error:        ErrorContent(model: model)
        }
    }
}
```

- [ ] **Step 3: Create `RecordingContent.swift`**

```swift
import SwiftUI

/// Orb · "Listening" + hint · waveform · timer (· Stop in toggle mode).
struct RecordingContent: View {
    let model: OverlayModel

    var body: some View {
        HStack(spacing: DS.Space.s12) {
            Orb(state: .recording)

            VStack(alignment: .leading, spacing: 1) {
                Text("Listening")
                    .font(DS.font(.bodyLarge))
                    .foregroundStyle(DS.Colors.text.color)
                Text(hint)
                    .font(DS.font(.caption))
                    .foregroundStyle(DS.Colors.muted.color)
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)

            Waveform(levels: model.levelHistory, bars: model.isToggleMode ? 12 : 20, tint: DS.Colors.rec.color)
                .frame(height: 22)

            RecordingTimer(startDate: model.recordingStart)

            if model.isToggleMode {
                Button("Stop") { model.onStop?() }
                    .buttonStyle(.dsSecondary)
            }
        }
    }

    private var hint: String {
        let key = model.hotkeyName.isEmpty ? "the hotkey" : model.hotkeyName
        return model.isToggleMode ? "Press \(key) again to finish" : "Release \(key) to finish"
    }
}

/// Elapsed time, updated once a second. Tabular digits so it does not jitter.
struct RecordingTimer: View {
    let startDate: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(startDate))
            Text(String(format: "%d:%02d", Int(elapsed) / 60, Int(elapsed) % 60))
                .font(DS.font(.value))
                .foregroundStyle(DS.Colors.text.color)
        }
    }
}
```

- [ ] **Step 4: Create `TranscribingContent.swift`**

```swift
import SwiftUI

/// Orb breathing · "Transcribing…" · thin indeterminate bar where the
/// waveform was, so the capsule keeps its height and nothing jumps.
struct TranscribingContent: View {
    var body: some View {
        HStack(spacing: DS.Space.s12) {
            Orb(state: .transcribing)

            Text("Transcribing…")
                .font(DS.font(.bodyLarge))
                .foregroundStyle(DS.Colors.text.color)
                .fixedSize()

            ProgressView()
                .progressViewStyle(.linear)
                .tint(DS.Colors.accent.color)
                .frame(height: 22)
        }
    }
}
```

- [ ] **Step 5: Create `ResultContent.swift`**

```swift
import SwiftUI

/// Orb done · text (up to 4 lines) · Copy · Show all · duration.
struct ResultContent: View {
    let model: OverlayModel

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.s12) {
            Orb(state: .done)

            VStack(alignment: .leading, spacing: DS.Space.s8) {
                Text(model.message)
                    .font(DS.font(.bodyLarge))
                    .foregroundStyle(DS.Colors.text.color)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: DS.Space.s12) {
                    if let onCopy = model.onCopy {
                        Button("Copy", action: onCopy).buttonStyle(.dsLink)
                    }
                    if let onShowAll = model.onShowAll {
                        Button("Show all", action: onShowAll).buttonStyle(.dsLink)
                    }
                    Spacer(minLength: 0)
                    Text(String(format: "%.1f s", model.durationSeconds))
                        .font(DS.font(.valueSmall))
                        .foregroundStyle(DS.Colors.muted.color)
                }
            }
        }
    }
}
```

- [ ] **Step 6: Create `ErrorContent.swift`**

```swift
import SwiftUI

/// Orb error · message · optional action button (e.g. Open System Settings).
struct ErrorContent: View {
    let model: OverlayModel

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.s12) {
            Orb(state: .error)

            Text(model.message)
                .font(DS.font(.bodyLarge))
                .foregroundStyle(DS.Colors.text.color)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let action = model.errorAction {
                Spacer(minLength: DS.Space.s8)
                Button(action.title, action: action.handler).buttonStyle(.dsSecondary)
            }
        }
    }
}
```

- [ ] **Step 7: Generate, build, run tests — expect PASS** (`Executed 33 tests`).

- [ ] **Step 8: Install and check live, all four states**

```bash
osascript -e 'quit app "SayVoice"'; sleep 2; rm -rf /Applications/SayVoice.app && cp -R build/Build/Products/Release/SayVoice.app /Applications/ && open /Applications/SayVoice.app
```

Then, with the app running:
1. Hold mode (Settings → Режим → Удержание): hold the hotkey, speak, release. Expect capsule with red orb pulsing, live waveform, timer; then breathing violet orb with a thin bar in the same capsule; then the card with the text, "Copy", "Show all" and the duration; it hides ~2 s later. Hover over the card before it hides — it must stay while the pointer is over it.
2. Toggle mode: press once, expect "Press ⌃⌥⌘D again to finish" and a "Stop" button; click Stop — recording ends and the result appears.
3. Switch the system to light appearance (System Settings → Appearance) and repeat 1 — glass border violet, text dark, shadow softer.
4. Error: temporarily deny Accessibility in System Settings, press the hotkey — the card shows the error (message text is still Russian at this phase; it comes from `AppCoordinator`, which is translated in the translation task). Re-enable Accessibility.

If the panel's card overflows 280 pt with a 4-line result plus actions, reduce `lineLimit` to 3 in `ResultContent` and note it in the commit.

- [ ] **Step 9: Commit**

```bash
git add -A SayVoice/Features/Overlay SayVoice/UI Tests/SayVoiceTests/OverlayRenderTests.swift SayVoice.xcodeproj
git commit -m "Rebuild the recording overlay on the design system

One glass panel of fixed width: a capsule for recording and transcribing,
a card for result and error. State is carried by the Orb; the waveform,
timer and Stop button share the capsule instead of stacking rows. Result
shows up to four lines with Copy and Show all."
```

---

### Task 10: Wire result and error actions through AppCoordinator and the menu bar

**Files:**
- Modify: `SayVoice/App/AppCoordinator.swift` (the `handleKeyUp` result branch and `handleStateChange` `.error` branch)
- Modify: `SayVoice/UI/MenuBarController.swift` (`showPopover()` → internal `showHistory()`)

**Interfaces:**
- Consumes: `OverlayWindowController.showResult(text:durationSeconds:onCopy:onShowAll:)`, `showError(message:action:)`, `PermissionManager.openAccessibilitySettings()`.
- Produces: `MenuBarController.showHistory()`.

- [ ] **Step 1: Expose the history popover**

In `SayVoice/UI/MenuBarController.swift` rename `private func showPopover()` to:

```swift
    /// Opens the history popover anchored to the status item. Also used by
    /// the overlay's "Show all" action.
    func showHistory() {
```

and update its two internal call sites (`togglePopover` calls `showPopover()` → `showHistory()`).

- [ ] **Step 2: Pass the actions from the coordinator**

In `SayVoice/App/AppCoordinator.swift`, in `handleKeyUp` replace the temporary line from Task 8 with:

```swift
                state = .injecting
                if settingsStore.overlayEnabled {
                    overlayController?.showResult(
                        text: text,
                        durationSeconds: durationSec,
                        onCopy: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        },
                        onShowAll: { [weak self] in
                            self?.overlayController?.dismiss()
                            self?.menuBarController?.showHistory()
                        }
                    )
                }
```

In `handleStateChange`, `.error` branch, replace `overlayController?.showError(message: msg)` with:

```swift
                if settingsStore.overlayEnabled {
                    let action: (title: String, handler: @MainActor () -> Void)? =
                        err == .accessibilityPermissionDenied
                            ? ("Open System Settings", { [weak self] in self?.permissionManager.openAccessibilitySettings() })
                            : nil
                    overlayController?.showError(message: msg, action: action)
                }
```

- [ ] **Step 3: Build, test, install, check**

```bash
xcodebuild -project SayVoice.xcodeproj -scheme SayVoice -configuration Release -derivedDataPath build build 2>&1 | grep -E "error:|BUILD"
xcodebuild -project SayVoice.xcodeproj -scheme SayVoice -derivedDataPath build test 2>&1 | grep -E "Executed|failed" | tail -2
osascript -e 'quit app "SayVoice"'; sleep 2; rm -rf /Applications/SayVoice.app && cp -R build/Build/Products/Release/SayVoice.app /Applications/ && open /Applications/SayVoice.app
```

Live: dictate, click **Copy** on the result card — paste elsewhere shows the text; dictate, click **Show all** — the overlay hides and the history popover opens under the menu bar icon.

- [ ] **Step 4: Commit**

```bash
git add SayVoice/App/AppCoordinator.swift SayVoice/UI/MenuBarController.swift SayVoice.xcodeproj
git commit -m "Wire overlay result actions and the accessibility error action"
```

---

### Task 11: Phase wrap-up — leftovers check and memory note

**Files:**
- Modify: none expected; verification only.

- [ ] **Step 1: Confirm no old overlay symbols remain and no literals leaked into the design system**

```bash
grep -rn "GlassCard\|PulsingDot\|BouncingDots\|StopButton\|EqualizerView" SayVoice || echo "no old overlay symbols"
grep -rn "Color(red:\|Color(nsColor:\|\.blue\b\|\.purple\b\|\.orange\b" SayVoice/DesignSystem/Components || echo "no literal colours in components"
grep -rln "[А-Яа-яЁё]" SayVoice/DesignSystem SayVoice/Features || echo "no Cyrillic in new files"
```

Expected: the three "no …" lines. (`Orb.swift` uses `Color(red:…)` for gradient highlights — that is inside `Orb.swift` only; if the second grep lists it, move those three literals into `Colors.swift` as `DS.Colors.recHighlight/okHighlight/warnHighlight` tokens and re-run.)

- [ ] **Step 2: Full test run and a final Release build**

```bash
xcodebuild -project SayVoice.xcodeproj -scheme SayVoice -derivedDataPath build test 2>&1 | grep -E "Executed|failed" | tail -2
xcodebuild -project SayVoice.xcodeproj -scheme SayVoice -configuration Release -derivedDataPath build build 2>&1 | grep -E "error:|BUILD"
git status --short
```

Expected: all tests pass, `BUILD SUCCEEDED`, clean tree.

- [ ] **Step 3: Record the phase in project memory** (ubimem `memory_ingest`, project scope): what landed (tokens, components, overlay), what stays transitional in `UI/`, and any deviations from this plan discovered during live checks.

---

## Self-review

**Spec coverage (Phase 1 scope):** §3.1 colours → Task 2; §3.2 typography + bundled fonts → Tasks 1–2; §3.3 spacing → Task 2; §3.4 motion → Tasks 2, 5, 9; §4 Orb/GlassPanel/Card/SettingsRow/Chip/KeyCap/Waveform/Buttons → Tasks 4–7; §4 ModelRow/DownloadProgress/EmptyState/TagField/HotkeyRecorder restyle → **Phase 2 plan** (settings) by design; §5.2 overlay → Tasks 8–10; §6 folder layout for DesignSystem and Features/Overlay → Tasks 2–9; §6 `AppWindow`, `.xcodeproj` removal → **Phase 3**; §9 tests → Tasks 1–7, 9; §9 screenshot script → **Phase 3**.

**Placeholder scan:** none. Every code step carries the full file or the exact replacement.

**Type consistency:** `DS.Colors.*` (Task 2) used in Tasks 4–9; `DS.font(.bodyLarge/.bodyMedium/.caption/.value/.valueSmall)` all declared in `DS.TextStyle`; `DS.Size.overlayWidth` used by `GlassPanel` and tests; `Orb.State` cases match `OverlayModel.DisplayState` usage in Task 9; `OverlayWindowController.panelSize` referenced by `OverlayRenderTests`; `showResult`/`showError` signatures identical between Task 8 (declaration), Task 8 step 3 (temporary call) and Task 10 (final call); `MenuBarController.showHistory()` declared in Task 10 and used in the same task.
