> **Historical** — describes SayVoice as of 2026-09-08, before the UI redesign. The root README and `docs/superpowers/specs/2026-09-09-ui-redesign-design.md` describe the current app.

# The file structure of the SayVoice project

## The project tree

```
SayVoice/
├── SayVoice.xcodeproj/
│
├── SayVoice/                                   ← the main target
│   │
│   ├── App/
│   │   ├── SayVoiceApp.swift                   ← the @main entry point
│   │   ├── AppCoordinator.swift                ← the orchestrator, the state machine
│   │   └── AppState.swift                      ← the enum of application states
│   │
│   ├── HotkeyListener/
│   │   ├── HotkeyListener.swift                ← CGEventTap, key-down/up
│   │   └── HotkeyError.swift                   ← hotkey registration errors
│   │
│   ├── Audio/
│   │   ├── AudioRecorder.swift                 ← an actor, AVAudioEngine, the PCM buffer
│   │   ├── AudioConverter.swift                ← AVAudioConverter into 16kHz f32
│   │   └── AudioError.swift
│   │
│   ├── Transcription/
│   │   ├── TranscriptionEngine.swift           ← an actor, the model lifecycle
│   │   └── TranscriptionError.swift
│   │
│   ├── TextInjection/
│   │   ├── TextInjector.swift                  ← the single entry point (AX → pasteboard)
│   │   ├── AXTextInjector.swift                ← the AXUIElement logic
│   │   └── PasteboardInjector.swift            ← the clipboard + a synthetic Cmd+V
│   │
│   ├── UI/
│   │   ├── MenuBarController.swift             ← NSStatusItem, the icon animation
│   │   ├── OverlayWindowController.swift       ← a floating NSPanel (non-activating)
│   │   ├── OverlayView.swift                   ← the SwiftUI view of the overlay
│   │   ├── MenuBarPopoverView.swift            ← the history + quick settings
│   │   └── SettingsView.swift                  ← the full settings screen
│   │
│   ├── Settings/
│   │   ├── SettingsStore.swift                 ← @Observable, UserDefaults
│   │   └── SettingsKeys.swift                  ← the string constants of the keys
│   │
│   ├── History/
│   │   ├── TranscriptionHistoryStore.swift     ← @Observable, JSON persistence
│   │   └── TranscriptionEntry.swift            ← the Codable struct of an entry
│   │
│   ├── Permissions/
│   │   └── PermissionManager.swift             ← checking + requesting Mic + AX
│   │
│   ├── ModelManagement/
│   │   ├── ModelManager.swift                  ← finding and downloading the model
│   │   └── ModelDownloadView.swift             ← the SwiftUI download screen
│   │
│   └── Resources/
│       ├── Assets.xcassets                     ← the icon, the menu bar template image
│       ├── SayVoice.entitlements               ← App Sandbox = NO
│       └── Info.plist                          ← LSUIElement, NSMicrophoneUsageDescription
│
└── Packages/
    └── CWhisper/                               ← the local SPM package
        ├── Package.swift
        └── Sources/
            ├── CWhisper/                       ← the C target (whisper.cpp + ggml)
            │   ├── include/
            │   │   └── whisper_bridge.h        ← the C API Swift sees
            │   ├── whisper.cpp
            │   ├── ggml.c
            │   ├── ggml-alloc.c
            │   ├── ggml-backend.cpp
            │   ├── ggml-quants.c
            │   ├── ggml-metal.m
            │   └── ggml-metal.metal
            └── WhisperSwift/                   ← the Swift target
                ├── WhisperContext.swift
                ├── WhisperTranscriber.swift
                └── WhisperError.swift
```

---

## A description of every file

### App/

**`SayVoiceApp.swift`**
The entry point (`@main`). Implements `NSApplicationDelegate`. Calls `NSApp.setActivationPolicy(.accessory)` — which removes the icon from the Dock. Contains no `WindowGroup`. Creates and holds the `AppCoordinator`.

**`AppCoordinator.swift`**
A `@MainActor final class`. The central orchestrator. Holds the current `AppState`. Reacts to the events from `HotkeyListener`, calls `AudioRecorder`, `TranscriptionEngine`, `TextInjector`. Publishes the state changes to the UI components.

**`AppState.swift`**
```swift
enum AppState {
    case idle
    case recording
    case transcribing
    case injecting
    case error(AppError)
}
```

---

### HotkeyListener/

**`HotkeyListener.swift`**
Creates a `CGEventTap` at the `.cgSessionEventTap` level. Checks `AXIsProcessTrustedWithOptions` at startup. Calls the `onKeyDown` / `onKeyUp` callbacks. A configurable keyCode (the default: 61 = Right Option). Manages the `CFMachPort` lifecycle.

**`HotkeyError.swift`**
```swift
enum HotkeyError: Error {
    case tapCreationFailed          // Accessibility not granted
    case accessibilityNotGranted    // the AX check failed
}
```

---

### Audio/

**`AudioRecorder.swift`**
An `actor`. Creates the `AVAudioEngine` and installs a tap on the `inputNode`. Holds a pre-allocated ring buffer for the PCM Float32 data. Methods: `startCapture() async throws`, `stopCapture() async -> [Float]`. The tap callback uses lock-free operations only.

**`AudioConverter.swift`**
Encapsulates the `AVAudioConverter` logic. Takes an `AVAudioPCMBuffer` in the hardware format (48kHz stereo, say) and returns an `AVAudioPCMBuffer` in the whisper format (16kHz mono Float32).

**`AudioError.swift`**
```swift
enum AudioError: Error {
    case engineStartFailed
    case formatConversionFailed
    case permissionDenied
    case noAudioInput
}
```

---

### Transcription/

**`TranscriptionEngine.swift`**
An `actor`. Loads the `WhisperContext` lazily on the first call. The method `transcribe(_ samples: [Float]) async throws -> String`. Handles cancellation (Task cancellation) on a timeout. Delegates to `WhisperTranscriber` from the SPM package.

**`TranscriptionError.swift`**
```swift
enum TranscriptionError: Error {
    case modelNotLoaded
    case modelLoadFailed(URL)
    case inferenceError
    case emptyResult
    case timeout
    case recordingTooShort        // < 0.3 sec (< 4800 samples)
}
```

---

### TextInjection/

**`TextInjector.swift`**
The single entry point. Takes `text: String`. Gets the PID of the frontmost application through `NSWorkspace.shared.frontmostApplication`. Tries `AXTextInjector` and falls back to `PasteboardInjector`. Appends a trailing space to the text.

**`AXTextInjector.swift`**
Implements the insertion through `AXUIElementCreateApplication(pid)` → `kAXFocusedUIElementAttribute` → `kAXSelectedTextAttribute`. Returns a `Bool` (success/failure). Handles the edge cases: no field focused, the attribute is not settable, a password field.

**`PasteboardInjector.swift`**
1. Saves `NSPasteboard.general.string(forType: .string)`
2. Writes our text
3. Creates synthetic `CGEvent`s (keyDown Cmd+V, keyUp Cmd+V) and posts them through `.cghidEventTap`
4. Restores the pasteboard after 300 ms

---

### UI/

**`MenuBarController.swift`**
A `@MainActor final class`. Creates an `NSStatusItem` with `variableStatusItemLength`. Reacts to `AppState` changes: updates the SF Symbol, the colour, the animation. A left click shows `MenuBarPopoverView`. A right click opens the menu (History, Settings, Quit).

**`OverlayWindowController.swift`**
A `@MainActor final class: NSWindowController`. Creates an `NSPanel` with the `.borderless`, `.nonactivatingPanel`, `.hudWindow` flags. Window level: `.floating`. Positioned in the lower part of the main screen. Methods: `show(message:isRecording:)`, `dismiss(animated:)`.

**`OverlayView.swift`**
A SwiftUI `View`. Shows a pulsing red dot while recording, plus the message text. The `.ultraThinMaterial` material, rounded corners. A fade-in animation on appearance.

**`MenuBarPopoverView.swift`**
A SwiftUI `View`. A list of the last 10 transcriptions with timestamps. Clicking an entry copies it to the pasteboard. A "Clear history" button. A "Settings…" link. Shown in an `NSPopover`.

**`SettingsView.swift`**
A SwiftUI `View`. Sections: the hotkey (a click-to-record picker), choosing the model, the language (Auto/EN/RU), the toggles (overlay, sound, insertion method). Opened through `NSApp.sendAction(Selector("showSettingsWindow:"), ...)` or from the popover.

---

### Settings/

**`SettingsStore.swift`**
An `@Observable final class`. Reads and writes `UserDefaults`. Publishes the changes to its subscribers. Properties: `hotkeyCode: Int`, `modelSize: String`, `language: String`, `overlayEnabled: Bool`, `soundFeedback: Bool`, `pasteMethod: String`, `launchAtLogin: Bool`.

**`SettingsKeys.swift`**
The string constants:
```swift
enum SettingsKeys {
    static let hotkeyCode     = "sv_hotkey_code"
    static let modelSize      = "sv_model_size"
    static let language       = "sv_language"
    static let overlayEnabled = "sv_overlay_enabled"
    static let soundFeedback  = "sv_sound_feedback"
    static let pasteMethod    = "sv_paste_method"
    static let launchAtLogin  = "sv_launch_at_login"
}
```

---

### History/

**`TranscriptionHistoryStore.swift`**
An `@Observable final class`. Holds `[TranscriptionEntry]` (max 500). Persists to `~/Library/Application Support/SayVoice/history.json`. Methods: `append(_:)`, `clear()`, `entries(last:)`.

**`TranscriptionEntry.swift`**
```swift
struct TranscriptionEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let text: String
    let durationSeconds: Double     // the length of the recording
    let language: String?           // the detected language ("ru", "en")
}
```

---

### Permissions/

**`PermissionManager.swift`**
A `@MainActor final class`. Methods:
- `requestMicrophone() async -> Bool`
- `isMicrophoneGranted: Bool` (computed)
- `isAccessibilityGranted: Bool`
- `requestAccessibilityPrompt()` — shows the system dialog
- `openAccessibilitySettings()` — opens System Settings
- `openMicrophoneSettings()` — opens System Settings

---

### ModelManagement/

**`ModelManager.swift`**
A `@MainActor final class`. The directory: `~/Library/Application Support/SayVoice/Models/`. Methods: `isModelAvailable(size:) -> Bool`, `downloadModel(size:) async throws` (which publishes the progress through an `AsyncStream<Double>`). The supported sizes: "tiny", "base", "small".

**`ModelDownloadView.swift`**
A SwiftUI `View`. A list of the available models with their sizes and characteristics. A "Download" button with a progress bar. Models already downloaded are shown with a tick.

---

### Resources/

**`Assets.xcassets`**
- `AppIcon.appiconset` — the application icon (1024x1024)
- `MenuBarIcon.imageset` — an 18x18pt template image for the menu bar (a black waveform on transparency)

**`SayVoice.entitlements`**
```xml
<key>com.apple.security.app-sandbox</key>
<false/>
```

**`Info.plist`** (the key entries)
```xml
<key>LSUIElement</key>          <!-- No icon in the Dock -->
<true/>
<key>NSMicrophoneUsageDescription</key>
<string>...</string>
<key>CFBundleDisplayName</key>
<string>SayVoice</string>
<key>LSMinimumSystemVersion</key>
<string>14.0</string>
```

---

### Packages/CWhisper/

**`Package.swift`**
Defines two targets: `CWhisper` (C/C++/ObjC) and `WhisperSwift` (Swift, depending on CWhisper). Compilation flags: `-std=c++17`, `-O3`, `GGML_USE_METAL`. Links Metal, Accelerate, CoreML.

**`whisper_bridge.h`**
The only public header of the C bridge. Defines `SayVoiceWhisperParams` and the functions `whisper_bridge_init`, `whisper_bridge_free`, `whisper_bridge_transcribe`, `whisper_bridge_free_string`. All of them `extern "C"`.

**`WhisperContext.swift`**
An `actor`. Holds an `OpaquePointer?` to `whisper_context*`. Initialised from the model URL. The method `transcribe(samples: [Float], language: String?) throws -> String`. Its `deinit` calls `whisper_bridge_free`.

**`WhisperTranscriber.swift`**
The high-level interface. Takes a `[Float]`, returns a `String`. Sets up `SayVoiceWhisperParams` (n_threads = ProcessInfo.processInfo.processorCount, language = -1 for auto).

**`WhisperError.swift`**
```swift
enum WhisperError: Error {
    case modelLoadFailed
    case transcriptionFailed
    case invalidSampleCount     // < whisper's minimum
}
```

---

## Totals

| Metric | Value |
|---|---|
| Swift files (the main target) | 25 |
| Swift files (the SPM package) | 3 |
| C/C++ files (vendored whisper.cpp) | 8 |
| External SPM dependencies | 0 |
| System frameworks | 10 |
