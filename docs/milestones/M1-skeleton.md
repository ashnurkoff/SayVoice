# M1 — The application skeleton (DONE)

**Goal:** a working macOS menu bar application with no Dock icon that reacts to a global hotkey. No transcription — only the skeleton with visual feedback.

**Estimate:** 2 working days
**Dependencies:** none (the first milestone)
**Definition of done:** hold Right Option → a red icon + the "Recording…" overlay → release → everything hides

---

## Tasks

### 1. Creating the Xcode project

- [x] The project through xcodegen (project.yml), Bundle ID: `com.sayvoice.app`
- [x] Deployment Target: macOS 14.0
- [x] The folder structure created per [file-structure.md](../file-structure.md)

### 2. Info.plist

- [x] `LSUIElement = true` — no icon in the Dock
- [x] `NSMicrophoneUsageDescription` — the description of the microphone access
- [x] `NSAppleEventsUsageDescription` — the description of the Accessibility access
- [x] `CFBundleIdentifier`, `CFBundleName`, `CFBundleVersion` and the other standard keys

### 3. Entitlements — switch off the sandbox

- [x] `com.apple.security.app-sandbox = false`

### 4. AppState.swift

- [x] `enum AppState: Equatable` — idle, recording, transcribing, injecting, error
- [x] `enum AppError: Error, Equatable` — every kind of error

### 5. SayVoiceApp.swift — the entry point

- [x] `@main struct SayVoiceApp: App` + `AppDelegate`
- [x] `NSApp.setActivationPolicy(.accessory)` — hiding from the Dock

### 6. MenuBarController.swift

- [x] An `NSStatusItem` with the "waveform" SF Symbol
- [x] A pulse animation while recording (waveform ↔ waveform.badge.mic.fill)
- [x] Colours: red (recording), orange (transcribing), green (injecting)
- [x] A menu with a "Quit SayVoice" item

### 7. OverlayView.swift + OverlayWindowController.swift

- [x] An `NSPanel` with `.borderless` + `.nonactivatingPanel` (it never steals focus)
- [x] A SwiftUI overlay with a pulsing red dot while recording
- [x] A `.regularMaterial` background, rounded corners, a shadow
- [x] A fade-in/fade-out animation
- [x] Positioned at the bottom of the screen

### 8. HotkeyListener.swift

- [x] `CGEvent.tapCreate()` for intercepting keys globally (the macOS 26 API)
- [x] Listens to `flagsChanged` (Right Option is a modifier, not a regular key)
- [x] keyCode and flags are extracted BEFORE the hop into `Task { @MainActor }` (Swift 6 Sendable)
- [x] The tap is reactivated automatically on `tapDisabledByTimeout`
- [x] `promptAccessibility()` — shows the system dialog when the permission is missing

### 9. AppCoordinator.swift

- [x] The state machine: idle → recording → idle (the M1 skeleton)
- [x] Coordinates MenuBarController, OverlayWindowController, HotkeyListener
- [x] A visible error in the overlay when Accessibility is missing

---

## Adapting to macOS 26 (Tahoe)

The code is adapted to the macOS 26.2 SDK (Xcode 16+):

- `CGEvent.tapCreate()` instead of `CGEventTapCreate()` (deprecated)
- `CGEvent.tapEnable(tap:enable:)` instead of `CGEventTapEnable()` (deprecated)
- `NSStatusItem.variableLength` instead of `.variableStatusItemLength` (deprecated)
- The string literal `"AXTrustedCheckOptionPrompt"` instead of the global variable (Swift 6 concurrency)
- Timer closures wrapped in `Task { @MainActor in }` (the @Sendable requirement)
- The NSAnimationContext completionHandler uses `MainActor.assumeIsolated {}`

---

## The M1 definition of done

- [x] The application launches — no icon in the Dock
- [x] The "waveform" icon appears in the menu bar
- [x] Without Accessibility: the overlay shows "No Accessibility access", plus the system dialog
- [x] With Accessibility: hold Right Option → the icon turns red, the "Recording…" overlay appears
- [x] Release Right Option → the icon turns grey, the overlay disappears with an animation
- [x] The menu → the "Quit" item works
- [x] 0 errors, 0 warnings when building against the macOS 26.2 SDK
