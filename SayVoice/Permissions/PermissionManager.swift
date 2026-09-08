import AppKit
import AVFAudio

@MainActor
final class PermissionManager {

    // MARK: - Microphone

    var isMicrophoneGranted: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    func requestMicrophone() async -> Bool {
        return await AVAudioApplication.requestRecordPermission()
    }

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Accessibility

    nonisolated var isAccessibilityGranted: Bool {
        let options = ["AXTrustedCheckOptionPrompt": false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    nonisolated func requestAccessibilityPrompt() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Reset stale TCC entry so macOS creates a fresh one for the current binary.
    /// Fixes the issue where Accessibility toggle is ON but AXIsProcessTrusted returns false
    /// after Xcode rebuilds (new binary = new ad-hoc signature).
    nonisolated func resetAccessibilityEntry() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", "com.sayvoice.app"]
        try? process.run()
        process.waitUntilExit()
        print("[SayVoice] Reset stale Accessibility entry via tccutil")
    }
}
