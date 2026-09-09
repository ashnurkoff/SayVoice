# The SayVoice technical stack

## 1. Platform and language

### Swift + SwiftUI (macOS 14.0+)

**Why not Electron / Tauri:**
- CGEventTap (the global hotkey) needs a native process without a web runtime
- AXUIElement (text insertion) is a native macOS API only
- Electron adds ~100-200 MB to the binary and hurts responsiveness
- SwiftUI + AppKit gives the better native feel and performance

**Why not Python + PyObjC:**
- Python needs a runtime (3.10+ with ~60 MB of dependencies)
- PyObjC is dated and supports async/await poorly
- Embedding whisper.cpp is harder (a Python package or a subprocess is needed)
- Slower for a production tool

**Swift 6 (strict concurrency):** every component uses `@MainActor`, `actor` and structured concurrency. That prevents data races at the compiler level.

---

## 2. Speech-to-text: whisper.cpp

### Integration: a local SPM package with a C bridge

**Why not the OpenAI Whisper API:**
- It needs the internet plus the user's API key
- It sends the audio to the cloud (a privacy problem)
- Network latency adds 1-3 sec to every request
- Cost: ~$0.006 per minute (which adds up with frequent use)

**Why not mlx-whisper:**
- It needs a Python runtime (incompatible with a native Swift application short of a subprocess)
- A subprocess adds IPC overhead and the complexity of managing a process

**Why whisper.cpp:**
- Written in C/C++ — called straight from Swift through a C bridge
- Metal GPU acceleration on Apple Silicon — ~2-3 sec for a 10-second phrase
- A mature project (ggerganov, 60k+ stars on GitHub)
- Supports every Whisper model unmodified

### The structure of the SPM package

```
Packages/
└── CWhisper/
    ├── Package.swift
    └── Sources/
        ├── CWhisper/                    ← the C target
        │   ├── include/
        │   │   └── whisper_bridge.h     ← the only header Swift sees
        │   ├── whisper.cpp              ← vendored (~10k lines)
        │   ├── ggml.c
        │   ├── ggml-alloc.c
        │   ├── ggml-backend.cpp
        │   ├── ggml-quants.c
        │   ├── ggml-metal.m             ← Objective-C for the Metal integration
        │   └── ggml-metal.metal         ← the Metal shaders
        └── WhisperSwift/                ← the Swift target
            ├── WhisperContext.swift     ← an actor, an OpaquePointer to the C struct
            ├── WhisperTranscriber.swift ← the high-level interface
            └── WhisperError.swift
```

### Package.swift (the key points)

```swift
// Swift/C++ interop requires the standard to be stated explicitly
.cxxLanguageStandard(.cxx17)

// The C target — compiler flags
.target(
    name: "CWhisper",
    cSettings: [
        .define("GGML_USE_METAL"),
        .unsafeFlags(["-O3", "-DNDEBUG"])
    ],
    linkerSettings: [
        .linkedFramework("Metal"),
        .linkedFramework("MetalKit"),
        .linkedFramework("Accelerate"),
        .linkedFramework("CoreML")
    ]
)
```

### whisper_bridge.h — the C bridge for Swift

```c
// This file is the only point of contact between Swift and whisper.cpp.
// Every C++ type, std::, namespace is hidden inside the .cpp files.
// Swift sees pure C only (extern "C").

#pragma once
#include <stdint.h>
#include <stdbool.h>

typedef struct whisper_context whisper_context;  // opaque

// Transcription parameters
typedef struct {
    int     n_threads;
    int     language;       // -1 = auto-detect
    bool    translate;      // true = translate into English
    bool    no_timestamps;
    float   temperature;    // 0.0 = deterministic mode
} SayVoiceWhisperParams;

// Lifecycle
whisper_context* whisper_bridge_init(const char* model_path);
void             whisper_bridge_free(whisper_context* ctx);

// Transcription (returns a heap string; free it through whisper_bridge_free_string)
char* whisper_bridge_transcribe(
    whisper_context*      ctx,
    const float*          samples,    // PCM Float32 @ 16kHz mono
    int32_t               n_samples,
    SayVoiceWhisperParams params
);
void whisper_bridge_free_string(char* str);
```

> **`no_timestamps` is always `false`.** Whisper decodes audio in 30-second
> windows and moves the window to the end of the last recognised segment.
> Without timestamp tokens the shift is forced to whole 30 seconds
> (`whisper.cpp`, `seek_delta = 100*WHISPER_CHUNK_SIZE`), and speech that falls
> on the seam between windows is decoded in neither of them — words went missing
> on dictations longer than 30 sec. The marks themselves never reach the text:
> the bridge assembles the segments through `whisper_full_get_segment_text` with
> `print_special = false`.

### Choosing the Whisper model

| Model | Size | Speed (M2 Pro) | RU quality | EN quality |
|---|---|---|---|---|
| tiny | 75 MB | ~0.5 sec | ★★☆☆☆ | ★★★☆☆ |
| base | 142 MB | ~0.8 sec | ★★★☆☆ | ★★★★☆ |
| **small** | **465 MB** | **~2-3 sec** | **★★★★☆** | **★★★★★** |
| medium | 1.5 GB | ~6-8 sec | ★★★★★ | ★★★★★ |
| large | 3 GB | ~15 sec | ★★★★★ | ★★★★★ |

**The choice for v1: `ggml-small.bin`** — the best balance of speed and quality for a personal tool. On an Intel Mac `ggml-base.bin` is recommended (shorter inference time without Metal).

**Where the model comes from:** Hugging Face — the `ggerganov/whisper.cpp` repository provides ready-made `.bin` files.

---

## 3. The global hotkey: CGEventTap

### Why not Carbon's `RegisterEventHotKey`

- The Carbon API is dated (deprecated in macOS 12, though it works)
- It cannot tell a key-down from a key-hold, which push-to-talk needs
- It requires a permanent event loop on the main thread
- It does not allow events to be modified or cancelled

### Why CGEventTap

```
The stream of HID events:
  Keyboard → IOKit → CGEventTap (ours) → EventQueue → the application
```

- Intercepts events BEFORE they are delivered to the application
- Plain `keyDown` and `keyUp` events (not only hotkey combinations)
- Works from any state of the system
- Does not need our application to have focus
- Tap level: `.cgSessionEventTap` — the level of the user session

**The default hotkey:** Right Option (keyCode 61) — it conflicts with no system shortcut and is comfortable to hold with the thumb.

---

## 4. Audio capture: AVAudioEngine

### Why not AVAudioRecorder

- `AVAudioRecorder` writes a file; there is no access to a real-time PCM buffer
- The format cannot be converted on the fly

### Why not CoreAudio HAL directly

- It takes ~200 lines of C code (AudioComponent, AudioUnit, callbacks)
- `AVAudioEngine` is a wrapper over CoreAudio — the same capabilities, less code

### The pipeline

```
The microphone (any sample rate, e.g. 48kHz stereo)
    │ installTapOnBus
    ▼
AVAudioConverter
    │ hardware format → 16,000 Hz / 1 ch / Float32
    ▼
A ring buffer (a pre-allocated [Float32])
    │ copied in the tap callback (lock-free)
    ▼
A [Float32] array → handed to whisper.cpp
```

---

## 5. Text insertion: a two-pronged strategy

### Strategy 1: AXUIElement (preferred)

```
AXUIElementCreateApplication(pid)
    └─► kAXFocusedUIElementAttribute → the focused element
          └─► kAXSelectedTextAttribute = our text
                (inserts at the caret, replaces the selection)
```

**Works in:** TextEdit, Notes, Xcode, Pages, Mail, the Safari URL bar, most native AppKit/SwiftUI fields.

### Strategy 2: the pasteboard + Cmd+V (the fallback)

```
1. Save NSPasteboard.general.string(forType: .string)
2. NSPasteboard.setString(ourText)
3. CGEvent keyDown(Cmd+V) → post(tap: .cghidEventTap)
4. CGEvent keyUp(Cmd+V)   → post(tap: .cghidEventTap)
5. Task.sleep(300ms)
6. Restore the pasteboard
```

**Works in:** Chrome, Electron (VS Code, the Notion app, Discord), Terminal, iTerm2, web forms.

**Does not work in:** password fields (deliberately blocked by macOS).

---

## 6. System frameworks

| Framework | Used for |
|---|---|
| `AVFoundation` / `AVFAudio` | `AVAudioEngine`, `AVAudioConverter`, `AVAudioPCMBuffer` |
| `CoreGraphics` | `CGEventTap` (the global hotkey), the synthetic Cmd+V events |
| `ApplicationServices` | `AXUIElement`, `AXUIElementCreateApplication` (text insertion) |
| `AppKit` | `NSStatusItem`, `NSPanel`, `NSPasteboard`, `NSSound`, `NSWorkspace` |
| `SwiftUI` | The overlay view, the Settings sheet, the History popover |
| `Metal` / `MetalKit` | Accelerating ggml (whisper.cpp) on Apple Silicon |
| `Accelerate` | The BLAS/vDSP operations in ggml |
| `CoreML` | Optional CoreML acceleration for whisper (Milestone 5) |
| `ServiceManagement` | `SMAppService.mainApp.register()` (launch at login) |
| `UserNotifications` | System notifications on errors (Milestone 5) |
| `Foundation` | `URLSession` (downloading the model), `UserDefaults`, `JSONEncoder` |

---

## 7. External dependencies

**The policy:** zero external SPM dependencies. Only:
1. The local `Packages/CWhisper/` package (vendored C code)
2. Apple's system frameworks (nothing external)

**The rationale:**
- No supply-chain security problems
- No network fetches on `swift package resolve`
- The project is entirely self-contained (it works offline once the model is downloaded)
- No breaking changes from dependency updates

---

## 8. Building and distribution

- **Xcode** 15.0+ (or 16.0+ for a macOS 14 target)
- **App Sandbox**: disabled (see [permissions.md](permissions.md))
- **Signing**: Developer ID Application (for distribution outside the App Store)
- **Distribution**: a plain `.dmg` / zip, through GitHub Releases
- **Notarisation**: needed for Gatekeeper (xcrun notarytool)

> For personal use a Developer ID signature is enough, or running unsigned (with the permission granted in System Settings > Privacy & Security).
