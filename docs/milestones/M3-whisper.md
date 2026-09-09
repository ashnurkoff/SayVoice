> **Historical** — describes SayVoice as of 2026-09-08, before the UI redesign. The root README and `docs/superpowers/specs/2026-09-09-ui-redesign-design.md` describe the current app.

# M3 — whisper.cpp integration

**Goal:** transcribe the captured audio locally through whisper.cpp with Metal acceleration. The result is a line of text in the console. Russian and English are both supported with no manual configuration.

**Estimate:** 3-4 working days (the hardest stage)
**Dependencies:** M2 finished (AudioRecorder returns `[Float]`)
**Definition of done:** "Hello, world" → "hello, world" in the console; a Russian phrase → that same Russian phrase — both without changing any setting

---

## Tasks

### 1. Getting the whisper.cpp sources

Download or clone a specific tag (not latest — for reproducibility):

```bash
# Option A: clone it
git clone --depth 1 --branch v1.7.4 https://github.com/ggerganov/whisper.cpp
cd whisper.cpp

# Option B: download the release archive
# https://github.com/ggerganov/whisper.cpp/releases/tag/v1.7.4
```

The files that have to be copied into `Packages/CWhisper/Sources/CWhisper/`:

| File | Where it is in the repository |
|---|---|
| `whisper.cpp` | `src/whisper.cpp`, or the root |
| `whisper.h` | `include/whisper.h` |
| `ggml.c` | `ggml/src/ggml.c` |
| `ggml.h` | `ggml/include/ggml.h` |
| `ggml-alloc.c` | `ggml/src/ggml-alloc.c` |
| `ggml-alloc.h` | `ggml/include/ggml-alloc.h` |
| `ggml-backend.cpp` | `ggml/src/ggml-backend.cpp` |
| `ggml-backend.h` | `ggml/include/ggml-backend.h` |
| `ggml-quants.c` | `ggml/src/ggml-quants.c` |
| `ggml-quants.h` | `ggml/include/ggml-quants.h` |
| `ggml-metal.m` | `ggml/src/ggml-metal.m` |
| `ggml-metal.metal` | `ggml/src/ggml-metal.metal` |

> **Careful:** the structure of the whisper.cpp repository changes between versions. In v1.7.x `ggml` has been moved into a subfolder. Check the current paths in the repository.

### 2. whisper_bridge.h — the C API for Swift

```c
// Packages/CWhisper/Sources/CWhisper/include/whisper_bridge.h
#pragma once
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// An opaque pointer to whisper_context (a C++ object, hidden from Swift)
typedef struct whisper_context whisper_context;

// Transcription parameters
typedef struct {
    int     n_threads;      // The number of CPU threads (recommended: ProcessorCount)
    int     language;       // -1 = auto-detect, otherwise the whisper language index
    bool    translate;      // Translate into English (false for us)
    bool    no_timestamps;  // true = do not add timestamps to the output
    float   temperature;    // 0.0 = deterministic, 1.0 = random
} SayVoiceWhisperParams;

// The model lifecycle
whisper_context* whisper_bridge_init(const char* model_path);
void             whisper_bridge_free(whisper_context* ctx);

// Transcription
// Returns a heap string (UTF-8). Free it through whisper_bridge_free_string().
// Returns NULL on an error.
char* whisper_bridge_transcribe(
    whisper_context*      ctx,
    const float*          samples,     // PCM Float32 @ 16kHz mono, [-1.0, 1.0]
    int32_t               n_samples,
    SayVoiceWhisperParams params
);
void whisper_bridge_free_string(char* str);

#ifdef __cplusplus
}
#endif
```

### 3. whisper_bridge.cpp — the implementation of the C bridge

```cpp
// Packages/CWhisper/Sources/CWhisper/whisper_bridge.cpp
// This file is compiled as C++ and connects the C API to the whisper.cpp API

#include "include/whisper_bridge.h"
#include "whisper.h"    // whisper.cpp public API
#include <cstring>
#include <string>

whisper_context* whisper_bridge_init(const char* model_path) {
    whisper_context_params params = whisper_context_default_params();
    params.use_gpu = true;   // switch Metal GPU on
    return whisper_init_from_file_with_params(model_path, params);
}

void whisper_bridge_free(whisper_context* ctx) {
    if (ctx) whisper_free(ctx);
}

char* whisper_bridge_transcribe(
    whisper_context*      ctx,
    const float*          samples,
    int32_t               n_samples,
    SayVoiceWhisperParams bridge_params
) {
    if (!ctx || !samples || n_samples <= 0) return nullptr;

    whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.n_threads        = bridge_params.n_threads;
    params.translate        = bridge_params.translate;
    params.no_timestamps    = bridge_params.no_timestamps;
    params.temperature      = bridge_params.temperature;
    params.print_realtime   = false;
    params.print_progress   = false;
    params.print_timestamps = false;
    params.print_special    = false;
    params.single_segment   = false;

    // Setting the language
    if (bridge_params.language == -1) {
        params.language = "auto";
    } else {
        // Kept simple: always auto (to be extended in M5)
        params.language = "auto";
    }

    int result = whisper_full(ctx, params, samples, n_samples);
    if (result != 0) return nullptr;

    // Assemble every segment into one string
    std::string output;
    const int n_segments = whisper_full_n_segments(ctx);
    for (int i = 0; i < n_segments; ++i) {
        const char* text = whisper_full_get_segment_text(ctx, i);
        if (text) {
            if (!output.empty() && output.back() != ' ') output += " ";
            output += text;
        }
    }

    // Trim whitespace
    size_t start = output.find_first_not_of(" \t\n\r");
    size_t end   = output.find_last_not_of(" \t\n\r");
    if (start == std::string::npos) return nullptr;
    output = output.substr(start, end - start + 1);

    if (output.empty()) return nullptr;

    // Return a heap string (Swift frees it through whisper_bridge_free_string)
    char* cstr = new char[output.size() + 1];
    std::strcpy(cstr, output.c_str());
    return cstr;
}

void whisper_bridge_free_string(char* str) {
    delete[] str;
}
```

### 4. Package.swift for CWhisper

```swift
// Packages/CWhisper/Package.swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CWhisper",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WhisperSwift", targets: ["WhisperSwift"])
    ],
    targets: [
        // C/C++/ObjC target — whisper.cpp + ggml
        .target(
            name: "CWhisper",
            path: "Sources/CWhisper",
            publicHeadersPath: "include",
            cSettings: [
                .define("GGML_USE_METAL"),
                .define("NDEBUG"),
                .headerSearchPath("."),  // for the include "whisper.h" inside the .cpp files
                .unsafeFlags(["-O3"])
            ],
            cxxSettings: [
                .define("GGML_USE_METAL"),
                .unsafeFlags(["-O3", "-std=c++17"])
            ],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Foundation"),
                .linkedFramework("CoreML")
            ]
        ),
        // The Swift wrapper
        .target(
            name: "WhisperSwift",
            dependencies: ["CWhisper"],
            path: "Sources/WhisperSwift"
        )
    ],
    cxxLanguageStandard: .cxx17
)
```

### 5. WhisperError.swift

```swift
// Packages/CWhisper/Sources/WhisperSwift/WhisperError.swift
import Foundation

enum WhisperError: Error, LocalizedError {
    case modelLoadFailed(String)    // the path to the model
    case transcriptionFailed
    case invalidSampleCount(Int)    // the number of samples received
    case contextIsNil

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let path): return "Could not load the model: \(path)"
        case .transcriptionFailed:       return "The transcription failed"
        case .invalidSampleCount(let n): return "An invalid number of samples: \(n)"
        case .contextIsNil:              return "The Whisper context is not initialised"
        }
    }
}
```

### 6. WhisperContext.swift

```swift
// Packages/CWhisper/Sources/WhisperSwift/WhisperContext.swift
import Foundation
import CWhisper

/// The actor isolates access to the whisper_context* C pointer.
/// Inference is NOT on the MainActor — it never blocks the UI.
actor WhisperContext {
    private var ctx: OpaquePointer?

    /// Initialisation from the model file. Takes ~1-5 sec (loading into memory + the Metal compilation).
    init(modelURL: URL) throws {
        let path = modelURL.path
        guard let context = whisper_bridge_init(path) else {
            throw WhisperError.modelLoadFailed(path)
        }
        self.ctx = OpaquePointer(context)
    }

    /// Transcribes [Float32] into a String.
    /// The call blocks the actor executor for the duration of the inference (~2-10 sec).
    func transcribe(samples: [Float], language: String = "auto") throws -> String {
        guard let ctx = self.ctx else {
            throw WhisperError.contextIsNil
        }

        guard samples.count > 0 else {
            throw WhisperError.invalidSampleCount(samples.count)
        }

        let params = SayVoiceWhisperParams(
            n_threads: Int32(ProcessInfo.processInfo.processorCount),
            language: -1,       // auto-detect
            translate: false,
            no_timestamps: true,
            temperature: 0.0
        )

        guard let rawResult = samples.withUnsafeBufferPointer({ ptr in
            whisper_bridge_transcribe(
                UnsafeMutablePointer(mutating: OpaquePointer(ctx) as UnsafePointer<whisper_context>),
                ptr.baseAddress,
                Int32(samples.count),
                params
            )
        }) else {
            throw WhisperError.transcriptionFailed
        }

        defer { whisper_bridge_free_string(rawResult) }
        let result = String(cString: rawResult)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    deinit {
        if let ctx = ctx {
            whisper_bridge_free(UnsafeMutablePointer(mutating: OpaquePointer(ctx) as UnsafePointer<whisper_context>))
        }
    }
}
```

> **A note:** casting between `OpaquePointer ↔ UnsafeMutablePointer<whisper_context>` needs care because of the C opaque structs. The exact code depends on the final whisper_bridge.h API.

### 7. WhisperTranscriber.swift

```swift
// Packages/CWhisper/Sources/WhisperSwift/WhisperTranscriber.swift
import Foundation

/// The high-level interface over WhisperContext
public final class WhisperTranscriber {
    private let context: WhisperContext

    public init(modelURL: URL) async throws {
        self.context = try await WhisperContext(modelURL: modelURL)
    }

    public func transcribe(_ samples: [Float]) async throws -> String {
        try await context.transcribe(samples: samples)
    }
}
```

### 8. TranscriptionError.swift (the main target)

```swift
// SayVoice/Transcription/TranscriptionError.swift
import Foundation

enum TranscriptionError: Error, LocalizedError {
    case modelNotLoaded
    case modelLoadFailed(URL)
    case inferenceError(Error)
    case emptyResult
    case timeout
    case recordingTooShort(Int)     // sample count

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:         return "The model is not loaded. Download it in the settings."
        case .modelLoadFailed(let u): return "Could not load the model: \(u.lastPathComponent)"
        case .inferenceError(let e):  return "Transcription failed: \(e.localizedDescription)"
        case .emptyResult:            return "Didn't catch anything"
        case .timeout:                return "Transcription timed out"
        case .recordingTooShort:      return ""   // ignore it silently
        }
    }
}
```

### 9. ModelManager.swift

```swift
// SayVoice/ModelManagement/ModelManager.swift
import Foundation

@MainActor
final class ModelManager: ObservableObject {

    enum ModelSize: String, CaseIterable {
        case tiny  = "ggml-tiny"
        case base  = "ggml-base"
        case small = "ggml-small"

        var fileSize: String {
            switch self {
            case .tiny:  return "75 MB"
            case .base:  return "142 MB"
            case .small: return "465 MB"
            }
        }

        var fileName: String { "\(rawValue).bin" }

        // The Hugging Face direct download URL (the ggerganov/whisper.cpp repository)
        var downloadURL: URL {
            URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
        }
    }

    static let modelsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("SayVoice/Models")
    }()

    func modelURL(for size: ModelSize) -> URL {
        Self.modelsDirectory.appendingPathComponent(size.fileName)
    }

    func isModelAvailable(_ size: ModelSize) -> Bool {
        FileManager.default.fileExists(atPath: modelURL(for: size).path)
    }

    func downloadModel(_ size: ModelSize) -> AsyncThrowingStream<Double, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try FileManager.default.createDirectory(
                        at: Self.modelsDirectory,
                        withIntermediateDirectories: true
                    )

                    let (bytes, response) = try await URLSession.shared.bytes(from: size.downloadURL)
                    let totalBytes = response.expectedContentLength

                    let tempURL = Self.modelsDirectory.appendingPathComponent(size.fileName + ".tmp")
                    guard FileManager.default.createFile(atPath: tempURL.path, contents: nil) else {
                        throw URLError(.cannotCreateFile)
                    }

                    let handle = try FileHandle(forWritingTo: tempURL)
                    defer { try? handle.close() }

                    var downloadedBytes: Int64 = 0
                    var chunk = Data()
                    chunk.reserveCapacity(65536)

                    for try await byte in bytes {
                        chunk.append(byte)
                        downloadedBytes += 1

                        if chunk.count >= 65536 {
                            try handle.write(contentsOf: chunk)
                            chunk.removeAll(keepingCapacity: true)

                            if totalBytes > 0 {
                                let progress = Double(downloadedBytes) / Double(totalBytes)
                                continuation.yield(progress)
                            }
                        }
                    }

                    if !chunk.isEmpty {
                        try handle.write(contentsOf: chunk)
                    }

                    // An atomic move from temp to the final place
                    let finalURL = Self.modelsDirectory.appendingPathComponent(size.fileName)
                    _ = try? FileManager.default.removeItem(at: finalURL)
                    try FileManager.default.moveItem(at: tempURL, to: finalURL)

                    continuation.yield(1.0)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
```

### 10. TranscriptionEngine.swift

```swift
// SayVoice/Transcription/TranscriptionEngine.swift
import Foundation
import WhisperSwift

actor TranscriptionEngine {
    private var transcriber: WhisperTranscriber?
    private let modelManager: ModelManager
    private let modelSize: ModelManager.ModelSize

    static let minimumSampleCount = 4800   // 0.3 sec @ 16kHz

    init(modelManager: ModelManager, modelSize: ModelManager.ModelSize = .small) {
        self.modelManager = modelManager
        self.modelSize = modelSize
    }

    func ensureLoaded() async throws {
        guard transcriber == nil else { return }

        let modelURL = await modelManager.modelURL(for: modelSize)
        guard await modelManager.isModelAvailable(modelSize) else {
            throw TranscriptionError.modelNotLoaded
        }

        transcriber = try await WhisperTranscriber(modelURL: modelURL)
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard samples.count >= Self.minimumSampleCount else {
            throw TranscriptionError.recordingTooShort(samples.count)
        }

        try await ensureLoaded()

        guard let transcriber else {
            throw TranscriptionError.modelNotLoaded
        }

        // A 15 sec timeout
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await transcriber.transcribe(samples)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(15))
                throw TranscriptionError.timeout
            }

            let result = try await group.next()!
            group.cancelAll()

            if result.isEmpty {
                throw TranscriptionError.emptyResult
            }
            return result
        }
    }
}
```

### 11. Wiring it into AppCoordinator (the M3 update)

```swift
// Add to AppCoordinator:
private let modelManager = ModelManager()
private lazy var transcriptionEngine = TranscriptionEngine(modelManager: modelManager)

// Update handleKeyUp():
func handleKeyUp() {
    guard state == .recording else { return }
    state = .transcribing

    Task {
        let samples = await audioRecorder.stopCapture()

        do {
            let text = try await transcriptionEngine.transcribe(samples)
            print("✅ Transcription: \(text)")
            overlayController?.show(message: text)
            overlayController?.dismiss(after: 2.0)
            state = .idle

        } catch TranscriptionError.recordingTooShort {
            state = .idle  // silently

        } catch TranscriptionError.modelNotLoaded {
            // TODO: show ModelDownloadView
            state = .error(.modelNotLoaded)

        } catch TranscriptionError.emptyResult {
            state = .error(.transcriptionFailed("Didn't catch anything"))

        } catch {
            state = .error(.transcriptionFailed(error.localizedDescription))
        }
    }
}
```

---

## Common compilation errors and their fixes

### "C++ header 'xxx.h' cannot be included in a Swift bridging header"

**Cause:** Swift cannot import C++ headers directly.
**Fix:** `whisper_bridge.h` has to be **pure C** (`extern "C"`, no `std::`, no `namespace`). whisper.h is included in the `.cpp` files only.

### "symbol not found: _whisper_init_from_file"

**Cause:** the SPM C target does not compile `.cpp` files.
**Fix:** make sure `whisper.cpp` and `ggml.c` sit in the `Sources/CWhisper/` folder (not in subfolders). SPM compiles every `.c`, `.cpp` and `.m` file in the target automatically.

### The Metal shaders do not compile

**Cause:** `ggml-metal.metal` has to be included in the target as a resource.
**The fix in Package.swift:**
```swift
resources: [.process("ggml-metal.metal")]
```

### "Use of undeclared type 'ggml_type'"

**Cause:** `whisper.cpp` includes `ggml.h`, but the path is not found.
**Fix:** add to `cSettings`:
```swift
.headerSearchPath(".")  // so that "ggml.h" resolves relative to CWhisper/
```

### Very slow inference (>20 sec)

**Cause:** the Metal GPU is not used (ggml is built without the flag).
**Fix:** make sure `GGML_USE_METAL` is defined in cSettings/cxxSettings. Check the console: whisper.cpp must print `ggml_metal_init: device=Apple M1...`.

---

## Downloading the model on the first run

The sequence:
1. `TranscriptionEngine.ensureLoaded()` → `ModelManager.isModelAvailable(.small)` → false
2. It throws `TranscriptionError.modelNotLoaded`
3. `AppCoordinator` catches it → shows `ModelDownloadView` in a popover/sheet
4. The user presses "Download" → `ModelManager.downloadModel(.small)` with progress
5. When it completes: calling `transcriptionEngine.ensureLoaded()` again loads the model

---

## The M3 definition of done

- [x] The project compiles with `Packages/CWhisper/` without errors — **0 errors, 0 warnings**
- [x] The console at startup: `ggml_metal_init: device=Apple M3 Pro` (Metal is active, on the GPU)
- [x] The first run: the model download screen opens — **ModelDownloadView automatically when the model is missing**
- [x] After the download: the model file exists at `~/Library/Application Support/SayVoice/Models/ggml-small.bin`
- [x] Say "Hello" → the console: `[SayVoice] Transcription: Hello.` — **EN auto-detection works**
- [x] Say the Russian for "hello" → the console prints that same Russian word — **RU auto-detection (p=0.846)**
- [x] Mixed speech → auto-detection: `params.language = "auto"` picks the language of the segment correctly
- [x] Silence / <0.3 sec → `recordingTooShort` without a crash (the threshold is 4800 samples = 0.3 sec)
- [x] Recording again right after the first one works (the model is loaded once and kept in the actor)

**Finished on: 2026-02-25**

---

## Implementation notes (differences from the plan)

### whisper.cpp v1.7.4 — the final configuration

1. **The Metal shader**: `GGML_METAL_EMBED_LIBRARY` — the shader is preprocessed (ggml-common.h + ggml-metal-impl.h inlined) and embedded as a C array in `ggml-metal-embed.c`. SPM `.process()` resources are not used.

2. **The headers are split across two directories:**
   - `include/` — `whisper_bridge.h` only (publicHeadersPath, visible from Swift)
   - `ggml-headers/` — whisper.h, ggml.h, ggml-alloc.h and the rest (internal, C/C++ only)

3. **The key Package.swift flags:**
   - `-fno-objc-arc` — ggml-metal.m uses manual reference counting
   - `-Wno-ambiguous-macro` — the MIN/MAX macro redefinition in ggml
   - `GGML_USE_ACCELERATE`, `ACCELERATE_NEW_LAPACK`, `ACCELERATE_LAPACK_ILP64`
   - `GGML_METAL_EMBED_LIBRARY` instead of loading the .metal file at runtime

4. **OpaquePointer**: `whisper_context` is a forward-declared C struct → Swift imports it as an `OpaquePointer`. A direct assignment `self.ctx = context`, with no double conversion.

5. **params.language = "auto"** (a string, not the int -1 of the original plan) — the whisper.cpp API takes a string.

6. **A custom log callback** (`sayvoice_log_callback`): it filters the whisper.cpp/ggml output down to errors plus the key diagnostic lines (GPU name, model size, the auto-detected language). Hundreds of lines of noise are gone.

7. **The ggml-metal.m patch**: `#if GGML_METAL_EMBED_LIBRARY → [NSBundle mainBundle]` instead of `SWIFTPM_MODULE_BUNDLE` (which does not exist without resources). The "skipping kernel" warnings for the bf16 kernels are silenced as well.

### The test phrase

```
"One, two, three. Radio check. My name is Alex."  (spoken in Russian)
```
The transcription is correct, the Metal GPU is active, the inference takes ~2-3 sec on an Apple M3 Pro.
