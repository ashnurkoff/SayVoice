> **Historical** — describes SayVoice as of 2026-09-08, before the UI redesign. The root README and `docs/superpowers/specs/2026-09-09-ui-redesign-design.md` describe the current app.

# M5 — Polish

**Goal:** a feature-complete v1.0 that is pleasant to use every day. Settings, the transcription history, sound feedback, onboarding, error handling.

**Estimate:** 3-5 working days
**Dependencies:** M4 finished (the full pipeline works)
**Definition of done:** the application can be used daily without opening Xcode

---

## 5a — Settings

### SettingsKeys.swift

```swift
// SayVoice/Settings/SettingsKeys.swift
enum SettingsKeys {
    static let hotkeyCode     = "sv_hotkey_code"
    static let modelSize      = "sv_model_size"
    static let language       = "sv_language"
    static let overlayEnabled = "sv_overlay_enabled"
    static let soundFeedback  = "sv_sound_feedback"
    static let pasteMethod    = "sv_paste_method"
    static let launchAtLogin  = "sv_launch_at_login"
    static let hasCompletedOnboarding = "sv_onboarding_done"
}
```

### SettingsStore.swift

```swift
// SayVoice/Settings/SettingsStore.swift
import Foundation
import Observation

@Observable
final class SettingsStore {

    // The hotkey (keyCode + modifiers)
    var hotkeyCode: Int {
        didSet { UserDefaults.standard.set(hotkeyCode, forKey: SettingsKeys.hotkeyCode) }
    }

    // The model: "tiny" | "base" | "small"
    var modelSize: String {
        didSet { UserDefaults.standard.set(modelSize, forKey: SettingsKeys.modelSize) }
    }

    // The language: "auto" | "ru" | "en"
    var language: String {
        didSet { UserDefaults.standard.set(language, forKey: SettingsKeys.language) }
    }

    var overlayEnabled: Bool {
        didSet { UserDefaults.standard.set(overlayEnabled, forKey: SettingsKeys.overlayEnabled) }
    }

    var soundFeedback: Bool {
        didSet { UserDefaults.standard.set(soundFeedback, forKey: SettingsKeys.soundFeedback) }
    }

    // "auto" | "ax" | "pasteboard"
    var pasteMethod: String {
        didSet { UserDefaults.standard.set(pasteMethod, forKey: SettingsKeys.pasteMethod) }
    }

    var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: SettingsKeys.launchAtLogin)
            updateLaunchAtLogin(enabled: launchAtLogin)
        }
    }

    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: SettingsKeys.hasCompletedOnboarding) }
    }

    init() {
        let defaults = UserDefaults.standard
        self.hotkeyCode     = defaults.object(forKey: SettingsKeys.hotkeyCode) as? Int ?? 61
        self.modelSize      = defaults.string(forKey: SettingsKeys.modelSize) ?? "small"
        self.language       = defaults.string(forKey: SettingsKeys.language) ?? "auto"
        self.overlayEnabled = defaults.object(forKey: SettingsKeys.overlayEnabled) as? Bool ?? true
        self.soundFeedback  = defaults.object(forKey: SettingsKeys.soundFeedback) as? Bool ?? true
        self.pasteMethod    = defaults.string(forKey: SettingsKeys.pasteMethod) ?? "auto"
        self.launchAtLogin  = defaults.bool(forKey: SettingsKeys.launchAtLogin)
        self.hasCompletedOnboarding = defaults.bool(forKey: SettingsKeys.hasCompletedOnboarding)
    }

    private func updateLaunchAtLogin(enabled: Bool) {
        // SMAppService (macOS 13+)
        // import ServiceManagement
        // if enabled {
        //     try? SMAppService.mainApp.register()
        // } else {
        //     try? SMAppService.mainApp.unregister()
        // }
    }
}
```

### SettingsView.swift

```swift
// SayVoice/UI/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var isRecordingHotkey = false

    var body: some View {
        Form {
            // MARK: - Hotkey
            Section("Hotkey") {
                LabeledContent("Recording hotkey") {
                    Button(hotkeyLabel) {
                        isRecordingHotkey.toggle()
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(isRecordingHotkey ? .red : .primary)
                }

                if isRecordingHotkey {
                    Text("Press a key to assign it…")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            // MARK: - Model
            Section("Recognition model") {
                Picker("Model", selection: Binding(
                    get: { settings.modelSize },
                    set: { settings.modelSize = $0 }
                )) {
                    Text("Tiny (75 MB, fast, less accurate)").tag("tiny")
                    Text("Base (142 MB, balanced)").tag("base")
                    Text("Small (465 MB, recommended)").tag("small")
                }
                .pickerStyle(.radioGroup)

                Text("The models are kept in ~/Library/Application Support/SayVoice/Models/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: - Language
            Section("Recognition language") {
                Picker("Language", selection: Binding(
                    get: { settings.language },
                    set: { settings.language = $0 }
                )) {
                    Text("Auto (detected automatically)").tag("auto")
                    Text("Russian").tag("ru")
                    Text("English").tag("en")
                }
                .pickerStyle(.radioGroup)
            }

            // MARK: - Interface
            Section("Interface") {
                Toggle("Show the overlay while recording", isOn: Binding(
                    get: { settings.overlayEnabled },
                    set: { settings.overlayEnabled = $0 }
                ))

                Toggle("Sound feedback", isOn: Binding(
                    get: { settings.soundFeedback },
                    set: { settings.soundFeedback = $0 }
                ))
            }

            // MARK: - Insertion
            Section("Text insertion method") {
                Picker("Method", selection: Binding(
                    get: { settings.pasteMethod },
                    set: { settings.pasteMethod = $0 }
                )) {
                    Text("Auto (AX → the pasteboard)").tag("auto")
                    Text("AX only (native applications)").tag("ax")
                    Text("The pasteboard only (universal)").tag("pasteboard")
                }
                .pickerStyle(.radioGroup)
            }

            // MARK: - System
            Section("System") {
                Toggle("Launch at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }
                ))
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 500)
    }

    private var hotkeyLabel: String {
        // In M5, render the keyCode nicely as the symbol of the key
        settings.hotkeyCode == 61 ? "⌥ Right Option" : "KeyCode: \(settings.hotkeyCode)"
    }
}
```

---

## 5b — The transcription history

### TranscriptionEntry.swift

```swift
// SayVoice/History/TranscriptionEntry.swift
import Foundation

struct TranscriptionEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let text: String
    let durationSeconds: Double
    let language: String?       // "ru", "en", nil = unknown
}
```

### TranscriptionHistoryStore.swift

```swift
// SayVoice/History/TranscriptionHistoryStore.swift
import Foundation
import Observation

@Observable
final class TranscriptionHistoryStore {
    private(set) var entries: [TranscriptionEntry] = []
    private let maxEntries = 500

    private static var storageURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SayVoice/history.json")
    }

    init() {
        load()
    }

    func append(_ entry: TranscriptionEntry) {
        entries.insert(entry, at: 0)   // the newest first
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    func recent(_ count: Int = 10) -> [TranscriptionEntry] {
        Array(entries.prefix(count))
    }

    private func save() {
        do {
            let dir = Self.storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entries)
            try data.write(to: Self.storageURL, options: .atomic)
        } catch {
            print("⚠️ History save failed: \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: Self.storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: Self.storageURL)
            entries = try JSONDecoder().decode([TranscriptionEntry].self, from: data)
        } catch {
            print("⚠️ History load failed: \(error)")
            entries = []
        }
    }
}
```

### MenuBarPopoverView.swift

```swift
// SayVoice/UI/MenuBarPopoverView.swift
import SwiftUI

struct MenuBarPopoverView: View {
    @Environment(TranscriptionHistoryStore.self) private var history
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The header
            HStack {
                Label("SayVoice", systemImage: "waveform")
                    .font(.headline)
                Spacer()
                Button(action: onOpenSettings) {
                    Image(systemName: "gear")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // The transcription history
            if history.entries.isEmpty {
                VStack {
                    Text("No entries")
                        .foregroundStyle(.secondary)
                    Text("Hold ⌥ Right Option to record")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(history.recent(10)) { entry in
                            HistoryRowView(entry: entry)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 300)
            }

            Divider()

            // The bottom bar
            HStack {
                if !history.entries.isEmpty {
                    Button("Clear the history") {
                        history.clear()
                    }
                    .foregroundStyle(.red)
                    .buttonStyle(.plain)
                    .font(.caption)
                }
                Spacer()
                Button("Settings…") {
                    onOpenSettings()
                }
                .buttonStyle(.plain)
                .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 320)
    }
}

struct HistoryRowView: View {
    let entry: TranscriptionEntry
    @State private var copied = false

    var body: some View {
        Button(action: copyToClipboard) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.text)
                        .font(.system(size: 12))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)

                    Text(entry.date, style: .relative) +
                    Text(" · \(entry.durationSeconds, format: .number.precision(.fractionLength(1)))s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        withAnimation {
            copied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
    }
}
```

---

## 5c — Sound feedback

```swift
// Add to AppCoordinator:
import AppKit

private func playStartSound() {
    guard settingsStore.soundFeedback else { return }
    NSSound(named: NSSound.Name("Tink"))?.play()
}

private func playStopSound() {
    guard settingsStore.soundFeedback else { return }
    NSSound(named: NSSound.Name("Pop"))?.play()
}

// Call them from handleStateChange:
case .recording:
    playStartSound()
    // ...

case .idle where oldState == .injecting:
    playStopSound()
    // ...
```

**The standard macOS system sounds:**
- `Tink` — a quiet click (the recording starts)
- `Pop` — a soft pop (it finishes)
- `Purr` — a purr (success)
- `Basso` — a low sound (an error)

---

## 5d — Error handling

### The transcription timeout

Already implemented in `TranscriptionEngine` through `withThrowingTaskGroup` — a 15 sec timeout.

### The recording is too short (< 0.3 sec)

```swift
// In TranscriptionEngine:
guard samples.count >= 4800 else {  // 0.3 sec × 16000 Hz
    throw TranscriptionError.recordingTooShort(samples.count)
}
// AppCoordinator: on .recordingTooShort → state = .idle (silently)
```

### An empty result from whisper

```swift
// In TranscriptionEngine:
if result.isEmpty {
    throw TranscriptionError.emptyResult
}
// AppCoordinator: the overlay "Didn't catch anything" for 2 sec → idle
```

### The model is not downloaded

```swift
// AppCoordinator:
} catch TranscriptionError.modelNotLoaded {
    menuBarController?.showPopoverWithDownload()
    state = .idle
}
```

### The table of every error and its UX response

| Error | The overlay text | Time | Action |
|---|---|---|---|
| `recordingTooShort` | — (silence) | — | Straight to IDLE |
| `emptyResult` | "Didn't catch anything" | 2 sec | IDLE |
| `timeout` | "Taking too long…" | 3 sec | IDLE |
| `modelNotLoaded` | "Download the model in the settings" | 3 sec | Open the popover |
| `microphonePermissionDenied` | "No microphone access" | 3 sec | A button that opens the settings |
| `accessibilityPermissionDenied` | "No Accessibility access" | 3 sec | A button that opens the settings |

---

## 5e — Launching at login

```swift
// SayVoice/Settings/SettingsStore.swift
import ServiceManagement

private func updateLaunchAtLogin(enabled: Bool) {
    do {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    } catch {
        print("⚠️ Launch at login failed: \(error)")
    }
}
```

**Requirements:**
- macOS 13.0+ (SMAppService — the new API that replaces a LaunchAgents plist)
- The application has to be signed (Developer ID)
- The user can manage it through System Settings > General > Login Items

---

## 5f — Onboarding on the first run

The sequence of screens is shown in `MenuBarPopoverView` as a `NavigationStack` or a series of `sheet`s.

### OnboardingView.swift

```swift
// SayVoice/UI/OnboardingView.swift
import SwiftUI

enum OnboardingStep {
    case microphone
    case accessibility
    case modelDownload
    case complete
}

struct OnboardingView: View {
    @Environment(PermissionManager.self) private var permissions
    @Environment(ModelManager.self) private var modelManager
    @Environment(SettingsStore.self) private var settings
    @State private var step: OnboardingStep = .microphone
    @State private var downloadProgress: Double = 0

    var body: some View {
        VStack(spacing: 20) {
            switch step {
            case .microphone:
                MicrophonePermissionStep(onNext: handleMicrophoneStep)

            case .accessibility:
                AccessibilityPermissionStep(onNext: handleAccessibilityStep)

            case .modelDownload:
                ModelDownloadStep(progress: downloadProgress, onDownload: startDownload)

            case .complete:
                CompleteStep(onDismiss: {
                    settings.hasCompletedOnboarding = true
                })
            }
        }
        .padding(20)
        .frame(width: 320)
        .onAppear { checkInitialStep() }
    }

    private func checkInitialStep() {
        if !permissions.isMicrophoneGranted {
            step = .microphone
        } else if !permissions.isAccessibilityGranted {
            step = .accessibility
        } else if !modelManager.isModelAvailable(.small) {
            step = .modelDownload
        } else {
            step = .complete
        }
    }

    private func handleMicrophoneStep() {
        Task {
            await permissions.requestMicrophone()
            if permissions.isMicrophoneGranted {
                step = permissions.isAccessibilityGranted ? .modelDownload : .accessibility
            }
        }
    }

    private func handleAccessibilityStep() {
        permissions.requestAccessibilityPrompt()
        // There is no callback — the user has to come back after enabling it by hand
        // We show a "Check again" button → the check runs again
    }

    private func startDownload() {
        Task {
            for try await progress in modelManager.downloadModel(.small) {
                downloadProgress = progress
            }
            step = .complete
        }
    }
}
```

**The onboarding steps:**

```
┌─────────────────────────────────────┐
│  🎙  Microphone access              │
│  SayVoice needs microphone access   │
│  to record your voice.              │
│                                     │
│         [Allow]                     │
└─────────────────────────────────────┘
            ↓ (once allowed)
┌─────────────────────────────────────┐
│  ♿  Accessibility                  │
│  Needed for the global hotkey       │
│  and for inserting the text.        │
│                                     │
│  [Open Settings]  [Check again]     │
└─────────────────────────────────────┘
            ↓ (once enabled)
┌─────────────────────────────────────┐
│  ⬇  The Whisper Small model         │
│  465 MB · good RU/EN quality        │
│                                     │
│  ████████░░░░  52%                  │
│                                     │
│         [Download]                  │
└─────────────────────────────────────┘
            ↓ (once downloaded)
┌─────────────────────────────────────┐
│  ✅  Ready!                         │
│                                     │
│  Hold ⌥ Right Option                │
│  to start recording.                │
│                                     │
│         [Start]                     │
└─────────────────────────────────────┘
```

---

## The M5 definition of done

### Settings
- [ ] SettingsView opens from the popover and through NSApp Settings
- [ ] Changing the hotkey takes effect without a restart
- [ ] Changing the model takes effect on the next transcription
- [ ] The "sound" toggle works: record with it on and with it off
- [ ] The "overlay" toggle works: the overlay is gone when it is off

### History
- [ ] The popover shows the last 10 entries
- [ ] A click on an entry → the text is copied, the icon turns into a ✓
- [ ] "Clear the history" → the list empties
- [ ] The history survives between launches

### Sounds
- [ ] The recording starts → Tink
- [ ] The transcription ends → Pop
- [ ] Silence on `recordingTooShort`

### Errors
- [ ] Every error shows an understandable message in the overlay
- [ ] After an error the application returns to IDLE without a restart
- [ ] The 15 sec timeout works (check it: feed in a very long silence)

### Onboarding
- [ ] The first run → the onboarding opens
- [ ] The second run (with onboarding = done) → no onboarding
- [ ] Every onboarding step works correctly
- [ ] After all the steps → the application is ready to work

### Launch at login
- [ ] The "Launch at login" toggle → it appears in System Settings > Login Items
- [ ] Once it is on: log out and back in → the application is running

---

## The final end-to-end check

1. A fresh install → onboarding → mic + accessibility + downloading the model
2. Open TextEdit → hold Right Option → say a short test phrase
3. Release → the overlay shows that phrase → the text lands in TextEdit
4. Open Chrome → repeat → the text is inserted through the pasteboard
5. Click the menu bar icon → the entry is visible in the history → a click copies it
6. Open the settings → change the language to "en" → check the transcription
7. Restart the application → the history is preserved
8. Switch the sound off in the settings → record → silence
9. Check the launch at login
