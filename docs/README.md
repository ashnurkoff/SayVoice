> **Historical** — describes SayVoice as of 2026-09-08, before the UI redesign. The root README and `docs/superpowers/specs/2026-09-09-ui-redesign-design.md` describe the current app.

# SayVoice

A native macOS application for on-device voice transcription. Hold the hotkey, say a phrase, release — the text appears in the active field instantly. No clouds, complete privacy.

---

## Key capabilities of v1.0

- **Push-to-talk** — hold Right Option, speak, release
- **Fully local** — whisper.cpp with Metal acceleration on Apple Silicon; no internet needed
- **Works everywhere** — a global hotkey from any application
- **Smart text insertion** — inserts at the caret through the Accessibility API, falling back to the pasteboard
- **A menu bar application** — no Dock icon, nothing in the way of the desktop
- **Russian + English** — automatic language detection, no settings
- **Transcription history** — the last 500 entries, stored locally

---

## How it works

```
[Hold Right Option]
        │
        ▼
  Microphone recording
  (AVAudioEngine → 16kHz mono Float32)
        │
[Release Right Option]
        │
        ▼
  Local transcription
  (whisper.cpp + the ggml-small model, ~2-3 sec on an M-series)
        │
        ▼
  Text insertion into the active field
  (AXUIElement → or the pasteboard + Cmd+V)
        │
        ▼
  The overlay shows the result for 1.5 sec
```

---

## System requirements

| Parameter | Minimum | Recommended |
|---|---|---|
| macOS | 14.0 (Sonoma) | 15.0+ |
| Processor | Intel Core i5 | Apple Silicon M1+ |
| RAM | 4 GB | 8 GB+ |
| Disk space | 600 MB | 1 GB (for the models) |
| Permissions | Microphone + Accessibility | — |

> **Important:** the application is not distributed through the Mac App Store — it needs the App Sandbox switched off for CGEventTap and the Accessibility API to work.

---

## Documentation

| File | Contents |
|---|---|
| [architecture.md](architecture.md) | Components, the state machine, data flow, Swift 6 patterns |
| [tech-stack.md](tech-stack.md) | The rationale for the stack, whisper.cpp integration, choosing a model |
| [permissions.md](permissions.md) | macOS permissions, onboarding, the App Sandbox |
| [file-structure.md](file-structure.md) | The tree of Swift files and modules |

### Milestones

| File | Goal | Estimate |
|---|---|---|
| [M1-skeleton.md](milestones/M1-skeleton.md) | Menu bar + the global hotkey | 2 days |
| [M2-audio.md](milestones/M2-audio.md) | Audio capture | 1-2 days |
| [M3-whisper.md](milestones/M3-whisper.md) | whisper.cpp integration | 3-4 days |
| [M4-text-injection.md](milestones/M4-text-injection.md) | Text insertion | 1-2 days |
| [M5-polish.md](milestones/M5-polish.md) | Settings, history, polish | 3-5 days |

---

## Roadmap

```
Week 1
  Day 1-2 ─── M1: Skeleton (menu bar, hotkey, overlay)
  Day 3-4 ─── M2: Audio (capture, conversion, debug WAV)

Week 2
  Day 1-4 ─── M3: Whisper (the hardest stage, the C++ bridge)
  Day 5   ─── M4: Text insertion

Week 3
  Day 1-5 ─── M5: Polish (settings, history, onboarding)
                    ↓
               v1.0 ready to use
```

**In total:** ~2.5–3 weeks of one Swift developer.

---

## Competitors (for reference)

- **Superwhisper** — the closest counterpart, paid ($8/month), cloud-based by default
- **AquaVoice** — focused on continuous dictation, not push-to-talk
- **Spokenly** — web-oriented, less of a system tool
