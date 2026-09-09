# M2 — Audio capture ✅ FINISHED

**Goal:** capture PCM audio from the microphone while the hotkey is held. Convert it into the whisper.cpp format: 16kHz, mono, Float32. Confirm the data is correct by saving a debug WAV file.

**Estimate:** 1-2 working days
**Dependencies:** M1 finished (AppCoordinator and HotkeyListener work)
**Status:** finished

---

## Files created

### SayVoice/Permissions/PermissionManager.swift
- `@MainActor final class PermissionManager`
- The microphone: `AVAudioApplication.requestRecordPermission()`
- Accessibility: `AXIsProcessTrustedWithOptions` with the literal `"AXTrustedCheckOptionPrompt"` (macOS 26 concurrency-safe)
- Methods that open System Settings for both permissions

### SayVoice/Audio/AudioError.swift
- `enum AudioError: Error, LocalizedError`
- Cases: `engineStartFailed`, `formatConversionFailed`, `permissionDenied`, `noAudioInput`, `tapAlreadyInstalled`

### SayVoice/Audio/AudioConverter.swift
- `final class AudioConverter: @unchecked Sendable`
- Converts any microphone format → 16kHz mono Float32 through `AVAudioConverter`
- **An RC high-pass filter (80 Hz cutoff)** — removes the DC offset, fan hum, and 50/60 Hz mains buzz
- `@unchecked Sendable` — used serially from the audio tap callback

### SayVoice/Audio/AudioRecorder.swift
- `actor AudioRecorder` — thread-safe accumulation of the PCM buffer
- `startCapture()` → `installTap(onBus:)` + `engine.start()`
- `stopCapture() -> [Float]` → `removeTap(onBus:)` + `engine.stop()` + returning the buffer
- `nonisolated appendBufferSync` — conversion on the audio thread, written through `Task { await self.append() }`
- The input format of the microphone is logged at startup

## Files changed

### SayVoice/App/AppCoordinator.swift
- `permissionManager` and `audioRecorder` added
- `handleKeyDown()` → `audioRecorder.startCapture()`
- `handleKeyUp()` → `audioRecorder.stopCapture()` + logging the peak/RMS + the debug WAV
- **The Accessibility fix**: `tccutil reset` to clear stale TCC entries after a rebuild (ad-hoc signing)
- Polling with `prompt: false` while waiting for the grant
- The debug WAV: RIFF/WAV written by hand (a 44-byte header + Int16 PCM), peak normalisation (gain up to 0.95)

### SayVoice/HotkeyListener/HotkeyListener.swift
- The `start(prompt:)` parameter added — it controls whether the system dialog is shown
- The guard `if eventTap != nil { return }` — protection against a double tap

---

## Problems and solutions

### 1. Accessibility keeps resetting itself
**Symptom:** `AXIsProcessTrusted` returns `false` even with the toggle switched on in System Settings.
**Cause:** ad-hoc code signing (`CODE_SIGN_IDENTITY: "-"`) — every rebuild produces a new signature, and the TCC database holds the old hash.
**Solution:** `tccutil reset Accessibility com.sayvoice.app` before the request — it removes the stale entry and macOS creates a fresh one for the current binary.

### 2. The debug WAV does not play (Float32)
**Symptom:** Quick Look / QuickTime Player show an error or play it quietly.
**Cause:** Float32 WAV is poorly supported by the standard macOS players.
**Solution:** write an Int16 PCM WAV by hand through `Data.write(to:)`, without AVAudioFile.

### 3. An AVAudioFile crash on Int16 buffers
**Symptom:** `EXC_BREAKPOINT` on `file.write(from: buffer)`, error -10877.
**Cause:** AVAudioFile does not support writing an Int16 `AVAudioPCMBuffer` directly.
**Solution:** bypass AVAudioFile entirely — write the WAV by hand (a RIFF header + raw bytes).

### 4. A quiet recording
**Symptom:** peak ~0.013, RMS ~0.001 — the built-in MacBook microphone records quietly.
**Solution:** peak normalisation to 0.95 in the debug WAV. whisper.cpp needs no normalisation — it works at any level.

---

## Technical details

### The audio format for whisper.cpp
- Sample rate: **16,000 Hz**
- Channels: **1 (mono)**
- Format: **PCM Float32**, the range [-1.0, 1.0]

### The real-time audio thread
`installTap(onBus:)` invokes the callback at real-time priority. Conversion plus a `Task{}` is acceptable for a personal tool. For production — use a lock-free ring buffer.

### The AVAudioEngine lifecycle
`engine.stop()` **does not remove** the tap. `removeTap(onBus: 0)` is needed before `stop()`.

---

## Adapting to macOS 26 (Tahoe)

### The renamed AVAudioNode APIs
- `installTapOnBus(_:bufferSize:format:block:)` → `installTap(onBus:bufferSize:format:block:)`
- `removeTapOnBus(_:)` → `removeTap(onBus:)`

### Swift 6 strict concurrency
- `AudioConverter` — `@unchecked Sendable` (called serially from the audio thread)
- `PermissionManager` — the string literal `"AXTrustedCheckOptionPrompt"` instead of `kAXTrustedCheckOptionPrompt`

---

## The M2 definition of done

- [x] Press the hotkey → the microphone is active
- [x] Release it → the console: `[SayVoice] Captured X samples (Y.Z sec)`
- [x] `samples.count > 0` for a recording longer than 0.5 sec
- [x] The debug WAV is saved to the Desktop and plays correctly (the speech is intelligible)
- [x] Recording again works without errors
- [x] A refused permission → a graceful error, no crash
- [x] Memory does not grow with each recording (the buffer is cleared after stopCapture)
- [x] The high-pass filter removes the low-frequency noise
