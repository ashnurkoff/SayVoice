> **Historical** — describes SayVoice as of 2026-09-08, before the UI redesign. The root README and `docs/superpowers/specs/2026-09-09-ui-redesign-design.md` describe the current app.

# SayVoice architecture

## 1. Component diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                        SayVoiceApp.swift                            │
│       @main · NSApplicationDelegate · activationPolicy: .accessory  │
└────────────────────────┬────────────────────────────────────────────┘
                         │ creates and owns
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│                  AppCoordinator  (@MainActor class)                 │
│                                                                     │
│  The single source of truth. Reacts to component events, drives     │
│  the state transitions, coordinates the calls.                      │
└──┬──────┬──────┬──────┬──────┬──────┬──────────────────────────────┘
   │      │      │      │      │      │
   │      │      │      │      │      └──► TranscriptionHistoryStore
   │      │      │      │      └─────────► SettingsStore
   │      │      │      └────────────────► TextInjector
   │      │      └───────────────────────► TranscriptionEngine  (actor)
   │      └──────────────────────────────► AudioRecorder        (actor)
   └─────────────────────────────────────► HotkeyListener
                                           MenuBarController
                                           OverlayWindowController
                                           PermissionManager
```

### Component responsibilities

| Component | Responsibility |
|---|---|
| `AppCoordinator` | The state machine, orchestration, the single source of truth |
| `HotkeyListener` | CGEventTap, key-down/up events, the hotkey configuration |
| `AudioRecorder` | AVAudioEngine, capturing PCM Float32 @ 16kHz mono |
| `TranscriptionEngine` | Loading the model, calling whisper.cpp, managing the actor lifecycle |
| `TextInjector` | AXUIElement insertion + the pasteboard fallback |
| `MenuBarController` | NSStatusItem, SF Symbol animation per state |
| `OverlayWindowController` | An NSPanel floating overlay that never takes focus |
| `SettingsStore` | @Observable, UserDefaults, the user's settings |
| `TranscriptionHistoryStore` | In-memory + JSON, the last 500 entries |
| `PermissionManager` | Requesting and checking Microphone + Accessibility |

---

## 2. State machine

```
                    ┌─────────────────────────────────────────────┐
                    │                   IDLE                      │
                    │  • Icon: "waveform" (grey, static)          │
                    │  • Overlay: hidden                          │
                    └──────────────────┬──────────────────────────┘
                                       │ hotkey keyDown
                                       ▼
                    ┌─────────────────────────────────────────────┐
                    │                RECORDING                    │
                    │  • AudioRecorder.startCapture()             │
                    │  • Icon: "waveform", red, pulsing           │
                    │  • Overlay: "● Recording…"                  │
                    └──────────────────┬──────────────────────────┘
                                       │ hotkey keyUp
                                       ▼
                    ┌─────────────────────────────────────────────┐
                    │              TRANSCRIBING                   │
                    │  • AudioRecorder.stopCapture() → [Float32]  │
                    │  • TranscriptionEngine.transcribe() async   │
                    │  • Icon: "ellipsis.circle", orange          │
                    │  • Overlay: "Transcribing…"                 │
                    └──────────────────┬──────────────────────────┘
                                       │ the resulting String
                                       ▼
                    ┌─────────────────────────────────────────────┐
                    │               INJECTING                     │
                    │  • TextInjector.inject(text)                │
                    │  • Overlay: shows the transcribed text      │
                    │    (green) for 1.5 sec                      │
                    └──────────────────┬──────────────────────────┘
                                       │ insertion finished
                                       ▼
                                     IDLE
```

### Transitions on errors

From **any** state, on an error → IDLE:

```
RECORDING    → microphone error    → Overlay: "Microphone error"     → IDLE
TRANSCRIBING → empty result        → Overlay: "Didn't catch anything" → IDLE
TRANSCRIBING → timeout (>10 sec)   → Overlay: "Timed out"            → IDLE
TRANSCRIBING → recording < 0.3 sec → silently ignored                → IDLE
INJECTING    → AX denied           → Overlay: "No AX access"         → IDLE
```

---

## 3. Data flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    The full data flow                           │
└─────────────────────────────────────────────────────────────────┘

[The user holds Right Option]
        │
        ▼
CGEventTap callback (an arbitrary thread)
  └─► Task { @MainActor in coordinator.handleKeyDown() }
        │
        ▼
AppCoordinator.handleKeyDown()
  └─► state = .recording
  └─► menuBarController.setState(.recording)
  └─► overlayController.show("● Recording…")
  └─► await audioRecorder.startCapture()
        │
        │   [AVAudioEngine installTapOnBus]
        │   [lock-free ring buffer ← PCM Float32 chunks @ 16kHz]
        │
[The user releases Right Option]
        │
        ▼
CGEventTap callback (an arbitrary thread)
  └─► Task { @MainActor in coordinator.handleKeyUp() }
        │
        ▼
AppCoordinator.handleKeyUp()
  └─► state = .transcribing
  └─► overlayController.show("Transcribing…")
  └─► let samples = await audioRecorder.stopCapture()  // → [Float32]
        │
        ▼
  [Check: samples.count < 4800? (< 0.3 sec) → IDLE, silently]
        │
        ▼
  await transcriptionEngine.transcribe(samples)
    └─► WhisperContext.transcribe([Float32])  // actor, background thread
          └─► the whisper_transcribe_pcm() C call
          └─► returns a String
        │
        ▼
AppCoordinator receives the String
  └─► state = .injecting
  └─► textInjector.inject(text: result)
        ├─► the AXUIElement attempt (kAXSelectedTextAttribute)
        │     success → inserted
        │     failure ↓
        └─► the pasteboard fallback
              └─► save the pasteboard → put the text on it
              └─► CGEvent: keyDown Cmd+V → keyUp Cmd+V
              └─► after 300 ms: restore the pasteboard
        │
        ▼
  overlayController.show(result, 1.5 sec → fade out)
  historyStore.append(TranscriptionEntry(...))
  state = .idle
```

---

## 4. Swift 6 concurrency patterns

### 4.1 Splitting the actors

```swift
// The main UI thread — @MainActor
@MainActor
final class AppCoordinator { ... }

@MainActor
final class MenuBarController { ... }

@MainActor
final class OverlayWindowController { ... }

// Isolated actors (not MainActor — they never block the UI)
actor AudioRecorder { ... }         // accumulating the PCM buffer
actor TranscriptionEngine { ... }   // the model lifecycle
actor WhisperContext { ... }        // the C pointer to whisper_context*
```

### 4.2 The CGEventTap → MainActor hop

```swift
// The CGEventTap callback is invoked on an arbitrary system thread.
// Never call AppCoordinator directly — only through a Task.
let callback: CGEventTapCallBack = { proxy, type, event, refcon in
    let coordinator = Unmanaged<AppCoordinator>.fromOpaque(refcon!).takeUnretainedValue()
    Task { @MainActor in
        coordinator.handle(type: type, event: event)
    }
    return Unmanaged.passRetained(event)
}
```

### 4.3 The AVAudioEngine tap — a real-time thread

```swift
// NOT allowed in the tap callback:
//   - Task { await actor.method() }  // may allocate
//   - Swift async/await calls
//   - Any allocation (especially on a real-time thread)
//
// Allowed:
//   - Writing into a pre-allocated lock-free ring buffer
//   - OSAtomicAdd for counters
//   - memcpy into a pre-allocated buffer

inputNode.installTapOnBus(0, bufferSize: 4096, format: fmt) { buffer, _ in
    // The minimum of work: copy the floats into the ring buffer
    self.ringBuffer.write(buffer)  // lock-free
}
```

### 4.4 Switching contexts

```swift
// AudioRecorder — an actor, called from the MainActor
func stopCapture() async -> [Float] {
    // Runs on the AudioRecorder actor executor
    engine.inputNode.removeTapOnBus(0)
    engine.stop()
    defer { pcmBuffer = [] }
    return pcmBuffer  // a copy
}

// TranscriptionEngine — an actor, holds the heavy WhisperContext
func transcribe(_ samples: [Float]) async throws -> String {
    // Runs on the TranscriptionEngine actor executor (not the MainActor!)
    guard let ctx = whisperContext else { throw TranscriptionError.modelNotLoaded }
    return try await ctx.transcribe(samples: samples)
}
```

---

## 5. Memory management

- **The whisper.cpp model** (~465 MB) is loaded once on first use and kept in memory for as long as the application runs (cheaper than loading it again while the app is up).
- `whisper_context*` is a raw C pointer, released through `whisper_free()` in the `deinit` of the `WhisperContext` actor.
- The PCM buffer is cleared after every transcription (`defer { pcmBuffer = [] }`).
- The transcription history holds at most 500 entries; the old ones are dropped as new ones arrive.

---

## 6. Errors and edge cases

| Situation | Handling |
|---|---|
| Accessibility not granted | `HotkeyListener` returns `.tapCreationFailed`; the onboarding flow |
| Microphone not granted | `PermissionManager` shows the system alert |
| The model is not downloaded | `TranscriptionEngine` throws `.modelNotLoaded`; `ModelDownloadView` opens |
| Recording < 0.3 sec | Silently ignored, back to IDLE |
| An empty result from Whisper | Overlay: "Didn't catch anything", back to IDLE |
| Transcription timeout | `Task.sleep` + cancellation after 10 sec |
| The AX insertion failed | An automatic fallback to the pasteboard, with no error for the user |
| The pasteboard failed | Logged; Overlay: "Could not insert the text" |
| A password field | AX returns an error; the fallback does not work either; the overlay warns |
