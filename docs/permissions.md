# macOS permissions

## Overview of the requirements

SayVoice needs two system permissions and a **disabled App Sandbox**:

| Permission | Purpose | How it is granted |
|---|---|---|
| Microphone | Capturing the voice through AVAudioEngine | The system dialog (automatic) |
| Accessibility | CGEventTap + AXUIElement text injection | By hand in System Settings |

---

## 1. Microphone

### Why

`AVAudioEngine.inputNode` needs permission to use the microphone. Without it `engine.start()` fails with an error.

### How to request it (Swift)

```swift
// macOS 14+
import AVFAudio

func requestMicrophonePermission() async -> Bool {
    return await AVAudioApplication.requestRecordPermission()
}

// Checking the current status (no dialog)
func checkMicrophoneStatus() -> AVAudioApplication.recordPermission {
    return AVAudioApplication.shared.recordPermission
}
// The possible values: .granted, .denied, .undetermined
```

### Info.plist

```xml
<key>NSMicrophoneUsageDescription</key>
<string>SayVoice uses the microphone to record your voice and transcribe speech into text.</string>
```

Without this key macOS crashes the application when the permission is requested.

### Behaviour on a refusal

If the user pressed "Don't Allow" → `AVAudioApplication.requestRecordPermission()` returns `false`. Asking again is impossible programmatically — System Settings has to be opened:

```swift
if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
    NSWorkspace.shared.open(url)
}
```

---

## 2. Accessibility

### Why

Two separate uses:

**a) CGEventTap — the global hotkey**
`CGEventTapCreate(tap: .cgSessionEventTap, ...)` returns `nil` without Accessibility. The application cannot receive keyboard events from other applications.

**b) AXUIElement — text insertion**
`AXUIElementCreateApplication(pid)` + `AXUIElementSetAttributeValue` needs Accessibility to change the contents of text fields in other applications.

### How to check it and guide the user

```swift
import ApplicationServices

func isAccessibilityGranted() -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

func requestAccessibilityWithPrompt() {
    // Shows the system dialog "SayVoice wants to control this computer"
    let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
    AXIsProcessTrustedWithOptions(options)
}

func openAccessibilitySettings() {
    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    NSWorkspace.shared.open(url)
}
```

### Important behaviour

- There is no Info.plist key (unlike the microphone) — no description can be supplied through the plist
- The user has to enable SayVoice **by hand** in `System Settings > Privacy & Security > Accessibility`
- **No restart** of the application is needed afterwards (the CGEventTap can simply be created again)
- When the permission changes (enabled/disabled) the application is notified through `NSWorkspace.shared.notificationCenter` (event: `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`)

### Input Monitoring (on some macOS versions)

On macOS 13+ a CGEventTap with `kCGHIDEventTap` may **additionally** require the Input Monitoring permission:

```swift
import IOKit.hid

func checkInputMonitoring() -> Bool {
    return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
}
```

If it is required — open `System Settings > Privacy & Security > Input Monitoring`.

---

## 3. App Sandbox — DISABLED

### Why it has to be switched off

| Feature | Requirement |
|---|---|
| `CGEventTapCreate(.cgSessionEventTap)` | No sandbox, or `com.apple.security.temporary-exception.mach-lookup.global-name` |
| `AXUIElementSetAttributeValue` into other processes | No sandbox |
| `CGEvent.post(tap: .cghidEventTap)` (the synthetic Cmd+V) | No sandbox |

A sandboxed application can only use `CGEventTapCreate(.cgAnnotatedSessionEventTap)` — that type only lets it "listen" to events, and a CGEventTap for a global hotkey with `.cgSessionEventTap` is out of reach.

### Consequences

- The app **cannot** be published on the Mac App Store
- A Developer ID signature is needed (or a local run)
- There are no automatic restrictions on file system access (that is the developer's responsibility)

### SayVoice.entitlements

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <!-- No other entitlements are needed for v1 -->
</dict>
</plist>
```

---

## 4. The onboarding flow (first run)

```
The application starts
      │
      ▼
PermissionManager.checkAll()
      │
      ├─► Microphone: .undetermined?
      │         └─► show the system dialog
      │               granted → ✓
      │               denied  → show the instructions + an "Open Settings" button
      │
      ├─► Accessibility: false?
      │         └─► show the explanation + an "Open Settings" button
      │               (wait for it to be enabled by hand)
      │               granted → ✓
      │
      ├─► The ggml-small.bin model is missing?
      │         └─► show ModelDownloadView
      │               download (~465 MB with a progress bar)
      │               done → ✓
      │
      ▼
The application is ready to work
(overlay: "SayVoice is ready. Hold ⌥R to record")
```

### The onboarding screens (SwiftUI sheets in the popover)

**Step 1 — Microphone:**
```
┌─────────────────────────────────────┐
│  🎙  Microphone access              │
│                                     │
│  SayVoice needs access to the       │
│  microphone to record your voice.   │
│                                     │
│  [Allow access]                     │
└─────────────────────────────────────┘
```

**Step 2 — Accessibility:**
```
┌─────────────────────────────────────┐
│  ♿  Accessibility                  │
│                                     │
│  Needed for:                        │
│  • The global hotkey                │
│  • Inserting the text               │
│                                     │
│  Enable SayVoice in:                │
│  System Settings > Privacy >        │
│  Accessibility                      │
│                                     │
│  [Open Settings]  [Check again]     │
└─────────────────────────────────────┘
```

**Step 3 — Downloading the model:**
```
┌─────────────────────────────────────┐
│  ⬇  Downloading the Whisper model   │
│                                     │
│  ggml-small (~465 MB)               │
│  ████████░░░░░░  52%                │
│                                     │
│  Downloaded once.                   │
│  Transcription works offline.       │
└─────────────────────────────────────┘
```

---

## 5. Summary table

| | Microphone | Accessibility | App Sandbox |
|---|---|---|---|
| **Method** | The system dialog | By hand in System Settings | Always off |
| **Info.plist key** | `NSMicrophoneUsageDescription` | — | — |
| **Check API** | `AVAudioApplication.shared.recordPermission` | `AXIsProcessTrustedWithOptions` | — |
| **Asking again** | Only through System Settings | No dialog, only System Settings | — |
| **On a refusal** | The application cannot record | The hotkey does not work, AX insertion does not work | No functionality at all |
