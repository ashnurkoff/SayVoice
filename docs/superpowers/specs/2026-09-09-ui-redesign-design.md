# SayVoice UI Redesign — Design Spec

**Date:** 2026-09-09
**Status:** Approved (design), pending implementation plan
**Direction:** B · Product (see references)

## 1. Goal

Replace every user-facing surface of SayVoice — settings, recording overlay, first-run onboarding, history popover, menu bar — with one coherent visual system, and restructure the UI code so that the system is expressed as a small component library rather than per-screen copies.

The app is being prepared for open source. The redesign therefore optimises for two readers at once: the person dictating (clarity, consistency, both themes) and the contributor (obvious file layout, components that can be edited without reading feature logic, screenshots generated from code).

### Non-goals

- No changes to audio capture, transcription, text injection, the hotkey listener, or storage. Everything fixed on 2026-09-08 stays as is.
- No new features beyond what the redesign requires (e.g. no history search backend beyond what the popover needs; no auto-update).
- No third-party UI libraries. Pure SwiftUI plus our own components.

## 2. Decisions

| Decision | Choice | Why |
|---|---|---|
| Minimum macOS | **26.0 (Tahoe)** — raised from 14.0 | Native Liquid Glass and current controls; one design with no fallbacks is easier to keep correct in an open-source codebase. |
| Visual direction | **B · Product** | Chosen by the owner from three live mockups. A standalone product identity carried by the brand violet from the app icon. |
| Fonts | **Onest** (text) + **JetBrains Mono** (values), bundled | Both support Cyrillic (history entries stay Russian even after the UI moves to English) and are OFL-licensed. System font remains the fallback if loading fails. |
| Theme tokens | Defined in Swift, not in an asset catalog | One reviewable file per token family; a 25-folder colorset catalog is worse to diff and review. |
| Language of new code | **English** — UI strings and comments — from the first line | Files are being rewritten anyway; writing them in Russian and translating tomorrow is double work. Untouched files are translated in a separate task. |

## 3. Design tokens

### 3.1 Colour

Every role has a dark and a light value. Components never use literals — only roles.

| Role | Dark | Light | Used for |
|---|---|---|---|
| `ground` | `#17171D` | `#F7F7FB` | Window background |
| `surface` | `#202029` | `#FFFFFF` | Cards, popover |
| `surface2` | `#282833` | `#F2F2F8` | Controls, chips, inset areas |
| `line` | white 7% | black 8% | Hairline dividers and borders |
| `text` | `#F1F1F6` | `#191A22` | Primary text |
| `muted` | `#9E9FB0` | `#6A6C80` | Secondary text |
| `faint` | `#64667A` | `#A7A9BA` | Tertiary text, placeholders |
| `accent` | `#7B7FF2` | `#5B5FD6` | Brand; see the three-places rule |
| `accent2` | `#A78BFA` | `#8B5CF6` | Gradient partner of `accent` (orb, logo only) |
| `accentSoft` | accent 16% | accent 12% | Selected row fill, key cap fill |
| `onAccent` | #FFFFFF | #FFFFFF | Text and glyphs on the accent gradient |
| `rec` | `#F5636F` | `#E8465A` | Recording state |
| `ok` | `#3ECF8E` | `#22A86B` | Success, "downloaded" |
| `warn` | `#E0A34A` | `#C4842A` | Warnings, recoverable errors |
| `glassFill` | surface 62% | white 62% | Overlay body fallback (the live overlay uses `glassEffect`, which supplies its own material) |
| `glassLine` | accent 28% | accent 30% | Overlay border |
| `glassHighlight` | white 22% | white 95% | 1px inner top highlight on glass |
| `glassShadow` | #281E78 35% | black 18% | Overlay drop shadow |
| `cardShadow` | black 12% | black 12% | Card drop shadow |
| `recHighlight` | `#FF8A8A` | `#FF8A8A` | Orb gradient highlight (recording) |
| `okHighlight` | `#8CEDB8` | `#8CEDB8` | Orb gradient highlight (done) |
| `warnHighlight` | `#F7C773` | `#F7C773` | Orb gradient highlight (error) |

**Three-places rule.** `accent` appears only as: (1) the orb and the logo, (2) the active or interactive control — selected row, on-state toggle, focused field border, and text actions (`.dsLink`, `.dsPrimary`), (3) the overlay glass — its border and its 10% tint. Headings, section icons, badges, body text, progress bars and dividers are neutral. Semantic colours (`rec`, `ok`, `warn`) are not the accent and do not count against the rule.

Exactly three text levels exist. If a fourth seems necessary, the layout is wrong.

### 3.2 Typography

| Style | Face | Size / weight | Used for |
|---|---|---|---|
| `display` | Onest | 24 / 700, tracking −0.02em | Onboarding step title |
| `section` | Onest | 22 / 700, tracking −0.02em | Settings section title |
| `title` | Onest | 17 / 600 | Card title, popover header |
| `bodyLarge` | Onest | 15 / 500 | Overlay result text, primary labels |
| `body` | Onest | 13 / 400–500 | Everything else |
| `caption` | Onest | 12 / 400 | Explanatory notes |
| `value` | JetBrains Mono | 14 / 500 | Timer, hotkey caps |
| `valueSmall` | JetBrains Mono | 12 / 500 | File sizes, durations, language tags |

Digits in `value` styles use tabular figures. Fonts are bundled under `Resources/Fonts/` with their OFL licence files alongside, registered via `ATSApplicationFontsPath` in `Info.plist`. `Typography.swift` exposes `DS.font(.body)` etc.; if a face is missing at runtime it falls back to the system font of the same size and weight, silently.

### 3.3 Spacing, radius, elevation

- Base unit 4. Spacing scale: 8 · 12 · 16 · 20 · 28.
- Radii: 6 (small controls, key caps) · 10 (rows) · 14 (cards) · 18 (overlay card) · capsule (pills, orb).
- Settings row height 44. Popover row min height 48.
- Elevation: cards `0 1px 2px black 12%`; overlay `0 20px 50px rgba(40,30,120,0.35)` on dark, `0 16px 40px black 18%` on light.

### 3.4 Motion

- State changes: 180 ms ease-out.
- Orb: spring (response 0.35, damping 0.7) between states; recording pulse 1.2 s; transcribing "breath" 1.6 s.
- Overlay result auto-dismiss: 2 s, paused while the pointer is over the panel (at most 10 s). Error cards: 3 s, or 8 s when they carry an action; tapping the action dismisses.
- `accessibilityReduceMotion`: pulse and breath are replaced by static colour; state changes become instant.

## 4. Component library (`DesignSystem/Components`)

Rule of boundaries: a component knows nothing about `SettingsStore`, `ModelManager`, `AppCoordinator` or any store. It takes plain values and closures. Feature views compose components and bind data.

| Component | Purpose | API sketch |
|---|---|---|
| `Orb` | Single state indicator used in overlay, popover header and status icon rendering | `Orb(state: .idle/.recording/.transcribing/.done/.error, size: CGFloat)` |
| `GlassPanel` | Liquid Glass container with tokenised tint, border and highlight | `GlassPanel(shape: .capsule/.card) { content }` |
| `Card` | Settings card with optional title/subtitle header | `Card(title:subtitle:) { rows }` |
| `SettingsRow` | Label + optional note on the left, control on the right, 44pt | `SettingsRow("Show overlay", note: "…") { Toggle(…) }` |
| `Chip` | Small capsule label | `Chip("recommended", style: .neutral/.accent/.ok/.warn)` |
| `KeyCap` | Monospace hotkey display | `KeyCap("⌃⌥⌘D")` |
| `ModelRow` | Selectable model: name, 5-step quality bar, size, downloaded mark; hosts `DownloadProgress` inline | `ModelRow(model:isSelected:isDownloaded:download:onSelect:)` |
| `DownloadProgress` | Progress, speed, remaining, cancel, retry — one implementation for settings and onboarding | `DownloadProgress(state: .idle/.running(progress,bytesPerSec)/.failed(msg)/.done, onStart:onCancel:onRetry:)` |
| `Waveform` | Live bars driven by level history; keeps the existing `BarEngine` smoothing | `Waveform(levels: [Float], bars: Int, tint:)` |
| `TagField` | Existing chip editor, restyled to tokens | unchanged API |
| `HotkeyRecorder` | Existing recorder, restyled; lives in Features/Settings/ because it depends on the Hotkey domain type | unchanged API |
| `EmptyState` | Icon + title + hint for empty history | `EmptyState(icon:title:hint:)` |
| Buttons | System `Button` styles with token colours: `.primary`, `.secondary`, `.link`, `.destructive` | `ButtonStyle` extensions |

`Badge`, `StopButton` and the local `caption()` extension that exist today are removed; their uses migrate to `Chip`, `Buttons` and `DS.font(.caption)`.

## 5. Surfaces

### 5.1 Settings window

- **Size** 780 × 600, not resizable. Icon rail 64 wide on the left, content on the right.
- **Sections** (rail order): General · Recognition · Dictionary · Insertion · System. Each section has a header: `section` title, one-line `muted` subtitle, and on the right a status pill "Ready · Turbo Q5" (orb `.idle` + text) that reflects app state and selected model.
- **General:** one card "Recording hotkey" containing `HotkeyRecorder` on one row and the Hold/Toggle segmented picker on the next, each a `SettingsRow`, with the mode note under the picker; one card with rows "Show overlay while recording" and "Sound feedback".
- **Recognition:** card "Model" with `ModelRow` per model (Base, Small, Large Turbo Q5 *recommended*, Large Turbo Q8, Large Turbo); selecting a model that is not on disk shows `DownloadProgress` inside its row. Card "Language" with the existing 12-entry menu picker and its note. This is the only section allowed to scroll.
- The default model on a fresh install is Large Turbo Q5 (`ModelSize.recommended`).
- **Dictionary:** card with `TagField` and the note explaining that terms are wrapped into a punctuated prompt.
- **Insertion:** card with "Method" segmented (Clipboard / Accessibility), "Restore clipboard after paste" toggle, and the two dynamic notes that exist today.
- **System:** rows "Open at login", version, "Source code" link, "Licenses" (opens a sheet listing whisper.cpp, Onest, JetBrains Mono).
- The window is created through `AppWindow.make(title:size:content:)` and kept as a single instance.

### 5.2 Recording overlay

- **Panel** stays 640 × 280 with the existing positioning and focus-avoidance logic (`OverlayWindowController`), unchanged.
- **Geometry:** a `GlassPanel(.capsule)` of fixed width 420 for `recording` and `transcribing`. `result` and `error` expand the same 420-wide panel downward into `GlassPanel(.card)`. Width never changes between states; only height does, animated.
- **Recording (hold mode):** `Orb(.recording)` · label "Listening" with sub-label "release ⌥ to finish" (hotkey name from settings) · `Waveform` · `value` timer.
- **Recording (toggle mode):** same, sub-label "press ⌃⌥⌘D again to finish", and a "Stop" `.secondary` button inside the capsule on the right. The panel accepts mouse events in the states that have controls or hover behaviour — toggle-mode recording, result, and error with an action — and is mouse-transparent otherwise.
- **Transcribing:** `Orb(.transcribing)` · "Transcribing…" · waveform replaced by a thin indeterminate bar of the same width so the layout does not jump.
- **Result:** `Orb(.done)` · text up to 4 lines in `bodyLarge` · action row: "Copy", "Show all" (opens the history popover), duration in `valueSmall`. Auto-dismiss 2 s, paused while hovered (at most 10 s).
- **Error:** `Orb(.error)` · message · optional action ("Open Settings" for the accessibility case).
- Glass: `.glassEffect(.regular.tint(accent.opacity(0.10)), in: shape)` with `glassLine` border and `glassHighlight` inner top line.

### 5.3 First run (onboarding)

- **Size** 640 × 360. Left: art panel 240 wide — `accent → accent2` gradient, large white waveform, progress dots at the bottom. Right: one step at a time.
- **Steps:** Welcome → Permissions → Model → Hotkey.
  - **Welcome:** name, one sentence on what it does, one sentence that everything runs locally. "Get started".
  - **Permissions:** two rows — Microphone, Accessibility — each with status (granted / not yet), and a button ("Allow" / "Open System Settings"). Accessibility is polled every second while the step is visible. **No skip:** the app cannot work without them, and pretending otherwise is dishonest.
  - **Model:** `ModelRow` list with Large Turbo Q5 preselected and marked recommended, plus Small and Large Turbo Q8 — a deliberate subset of three; the full list of five lives in Settings → Recognition. `DownloadProgress` inline. Skip allowed ("Download later" — the settings window will offer it).
  - **Hotkey:** `HotkeyRecorder` with the current default (Right ⌥) and the Hold/Toggle picker. Skip allowed.
- Finish: closes the window, starts the normal flow. The stale "Whisper Small · 465 MB" and "hold Right Option" copy is gone; everything reads from settings.

### 5.4 History popover

- **Width** 320. Header: logo mark + "SayVoice" + status pill. Search field. List rows: text (2-line clamp), meta line in `valueSmall` — coarse relative time ("just now", "5 min", "yesterday"), duration, language tag when known. Copy action appears on hover; a brief "Copied" state replaces it.
- Footer: "Clear…" (`.destructive`, asks for confirmation) and "Settings". The gear icon in the header is removed — one entry point.
- Empty: `EmptyState` with the current hotkey name in the hint.

### 5.5 Model download

The separate window and `ModelDownloadView.swift` are removed. When the selected model is missing at launch or at transcription time, the app opens Settings → Recognition with that model's row outlined (`warn` border) and its `DownloadProgress` ready; `ModelDownloads` owns the transfer and cancellation. Onboarding (Phase 3) uses the same component and coordinator.

### 5.6 Menu bar

- Idle: template microphone glyph (unchanged).
- Recording: microphone + steady `rec` dot; transcribing: microphone + steady `accent` dot; error: warning glyph. The 0.4 s blinking is removed so the menu bar uses the same state language as the orb.
- Right-click menu: Settings… (⌘,), About SayVoice (opens Settings → System), Quit. "Download model…" is removed.

## 6. Code architecture

```
SayVoice/
  App/                    SayVoiceApp · AppCoordinator · AppState · AppStatus · AppWindow (new helper)
  DesignSystem/
    Tokens/               Colors.swift · Typography.swift · Spacing.swift · Motion.swift
    Components/           Orb · GlassPanel · Card · SettingsRow · Chip · KeyCap · ModelRow
                          DownloadProgress · Waveform · TagField · EmptyState · Buttons
  Features/
    Settings/             SettingsView · SettingsRail · GeneralSection · RecognitionSection
                          DictionarySection · InsertionSection · SystemSection · LicensesSheet
                          HotkeyRecorder · ModelDownloads · SettingsRouter · SettingsSection
                          SectionHeader
    Overlay/              OverlayWindowController · OverlayModel · OverlayView
                          RecordingContent · TranscribingContent · ResultContent · ErrorContent
    Onboarding/           OnboardingView · OnboardingModel · ArtPanel · WelcomeStep
                          PermissionsStep · ModelStep · HotkeyStep
    History/              HistoryPopover · HistoryRow · HistoryFilter · RelativeTime
    MenuBar/              MenuBarController · StatusIcon
  Audio/ Transcription/ TextInjection/ HotkeyListener/ Permissions/ ModelManagement/ History/ Settings/
                          unchanged (ModelDownloadView.swift removed from ModelManagement)
  Resources/
    Fonts/                Onest-*.ttf · JetBrainsMono-*.ttf · OFL.txt for each
    Licenses/             whisper.cpp-LICENSE.txt
```

- `DesignSystem` has no imports from `Features`, `App` or any store — it depends only on SwiftUI/AppKit. Enforced by review.
- Colour tokens: `enum DS.Color` with `static let ground: SwiftUI.Color` built from `NSColor(name:dynamicProvider:)` returning the dark or light literal by `effectiveAppearance`.
- Windows: `AppWindow.make(title:size:content:)` replaces the three hand-written `NSWindow` blocks in `AppCoordinator`; behaviour (centre, non-releasing, activate) is preserved.
- `project.yml`: deployment target → `26.0`; `Info.plist` gains `ATSApplicationFontsPath = Fonts`; a `SayVoiceTests` target is added.
- `SayVoice.xcodeproj` is removed from git and added to `.gitignore`; README documents `xcodegen generate`.

## 7. Removals

| Removed | Replaced by |
|---|---|
| `ModelManagement/ModelDownloadView.swift` | `DownloadProgress` inside `ModelRow` |
| `Badge`, `ModelRow`, `caption()` inside `SettingsView.swift` | `Chip`, `ModelRow`, `DS.font(.caption)` in `DesignSystem` |
| `TagChip` stays private to `TagField` — a removable chip with a hover state is not a `Chip`; both use the same tokens. | — |
| `StopButton`, `GlassCard`, `PulsingDot`, `BouncingDots` inside `OverlayView.swift` | `Buttons.secondary`, `GlassPanel`, `Orb` |
| Model download step inside `OnboardingView.swift` | `ModelStep` using `ModelRow` + `DownloadProgress` |
| Three `NSWindow` construction blocks in `AppCoordinator` | `AppWindow.make` |
| `#available(macOS 26.0, *)` branches | Removed; target is 26.0 |
| Blinking status-icon timer in `MenuBarController` | Static state icons |
| Committed `SayVoice.xcodeproj` | Generated locally via XcodeGen |

## 8. Language policy

All files created or rewritten by this work are in English: UI strings, comments, doc comments, identifiers. Files not touched by the redesign (audio, whisper bridge, hotkey listener, injectors, stores) keep their current Russian comments until the separate translation task. No file mixes the two.

## 9. Testing and screenshots

- **`SayVoiceTests`** (new target, XCTest): pure-logic tests migrated from yesterday's scratch scripts — `HotkeyEventDecision`, `SilenceTrimmer` (real-speech guard, click rejection, short-phrase survival), `TagField.tokens/string` round-trip, `TranscriptionEngine.initialPrompt`. No UI, no audio device, runs in seconds.
- **Screenshots**: a test-target harness (`SurfaceScreenshotTests`) driven by `Scripts/render-surfaces` renders every surface in both themes to `docs/screenshots/<surface>-<theme>.png` using the offline `NSHostingView` renderer developed during the audit. Used to check layout after changes and to keep README screenshots generated from code. Known limits are documented in the harness header: glass is rendered as the flat `glassFill` fallback; prominent buttons render inactive.

## 10. Implementation order

1. Tokens, fonts, `Buttons`, `Chip`, `KeyCap`, `Orb`, `GlassPanel`, `Card`, `SettingsRow` — and the test target skeleton.
2. Overlay (most visible; verified live in all four states, both modes).
3. Settings (rail + five sections), `ModelRow` + `DownloadProgress`, removal of the download window.
4. Onboarding (four steps, art panel).
5. History popover and menu bar icons/menu.
6. `AppWindow` helper, deletions, `.xcodeproj` out of git, README note, screenshot script, screenshots committed.

Each stage ends with a build, the test suite and a commit; the owner installs once at the end of the redesign and runs the live checks listed in the final report.

## 11. References

- UI audit board (all current surfaces, both themes, findings): https://claude.ai/code/artifact/539deeed-72c0-4790-8d50-2d8de84b040d
- Design directions (A/B/C live mockups, theme toggle, comparison): https://claude.ai/code/artifact/552f8496-74e9-425f-81e8-e5170ab56fda
