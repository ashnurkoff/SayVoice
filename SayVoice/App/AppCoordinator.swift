import AppKit
import AVFAudio
import SwiftUI

@MainActor
final class AppCoordinator {
    private var state: AppState = .idle {
        didSet { handleStateChange(from: oldValue, to: state) }
    }

    private var menuBarController: MenuBarController?
    private var overlayController: OverlayWindowController?
    private var hotkeyListener: HotkeyListener?
    private let permissionManager = PermissionManager()
    private let audioRecorder = AudioRecorder()
    private let modelManager = ModelManager()
    private lazy var transcriptionEngine = TranscriptionEngine(modelManager: modelManager)
    private let textInjector = TextInjector()
    private let settingsStore = SettingsStore()
    private let historyStore = TranscriptionHistoryStore()
    private var accessibilityPollTask: Task<Void, Never>?
    private var settingsWindow: NSWindow?
    private let status = AppStatus()
    private let settingsRouter = SettingsRouter()
    private lazy var modelDownloads = ModelDownloads(modelManager: modelManager)

    /// The application the dictation started in. The text goes there, not
    /// wherever the user has ended up by the time it finishes: in toggle mode a
    /// recording runs for a long time, and switching windows meanwhile is easy.
    private var recordingTargetApp: NSRunningApplication?
    private var onboardingWindow: NSWindow?
    /// `willClose` observer for the onboarding window, filtered by that
    /// window so no other window's close can trip it.
    private var onboardingCloseObserver: NSObjectProtocol?

    func start() {
        menuBarController = MenuBarController(status: status)
        menuBarController?.hotkeyName = settingsStore.hotkey.displayName
        menuBarController?.onQuit = { NSApp.terminate(nil) }
        menuBarController?.onShowSettings = { [weak self] in self?.showSettings() }
        menuBarController?.onShowAbout = { [weak self] in self?.showSettings(section: .system) }
        menuBarController?.onClearHistory = { [weak self] in
            self?.historyStore.clear()
            self?.menuBarController?.historyEntries = []
        }
        menuBarController?.onPopoverWillShow = { [weak self] in
            guard let self else { return }
            self.menuBarController?.historyEntries = self.historyStore.entries
        }

        overlayController = OverlayWindowController()

        hotkeyListener = HotkeyListener(coordinator: self)
        hotkeyListener?.apply(settingsStore.hotkey)
        hotkeyListener?.apply(isToggle: settingsStore.hotkeyIsToggle)

        status.modelName = (ModelManager.ModelSize(settingsString: settingsStore.modelSize) ?? .recommended).displayName
        modelDownloads.onCompleted = { [weak self] _ in
            guard let self else { return }
            if case .error(.modelNotLoaded) = self.state { self.state = .idle }
        }

        // Onboarding: show wizard on first launch, then proceed with normal startup
        if !settingsStore.hasCompletedOnboarding {
            showOnboardingWindow()
        } else {
            startHotkeyAndPermissions()
        }
    }

    // MARK: - Normal Startup Flow

    /// Sequential startup: Accessibility → Microphone → Model.
    /// Each step waits for the previous one to avoid dialog pile-up.
    private func startHotkeyAndPermissions() {
        // Step 1: Accessibility
        do {
            try hotkeyListener?.start(prompt: false)
            print("[SayVoice] Started successfully. Press Right Option to record.")
            continueStartupAfterAccessibility()
        } catch {
            // Only reset TCC if accessibility is NOT granted (stale entry from old binary).
            // Don't reset if permission IS granted (e.g. fresh grant from onboarding).
            if !permissionManager.isAccessibilityGranted {
                resetAccessibilityEntry()
            }

            do {
                try hotkeyListener?.start(prompt: true)
                print("[SayVoice] Started after fresh Accessibility grant.")
                continueStartupAfterAccessibility()
            } catch {
                print("[SayVoice] Accessibility not granted — waiting for user to enable in System Settings...")
                state = .error(.accessibilityPermissionDenied)
                startAccessibilityPolling()
                // continueStartupAfterAccessibility() is called from the polling success
            }
        }
    }

    /// A single press in toggle mode: it starts or stops the recording.
    func handleHotkeyToggle() {
        switch state {
        case .idle:      handleKeyDown()
        case .recording: handleKeyUp()
        default:         break   // transcribing or inserting — the press is ignored
        }
    }

    func handleKeyDown() {
        guard state == .idle else { return }
        recordingTargetApp = NSWorkspace.shared.frontmostApplication
        state = .recording

        Task {
            do {
                let onLevel: (@Sendable (Float) -> Void)?
                if settingsStore.overlayEnabled {
                    onLevel = { [weak self] level in
                        Task { @MainActor [weak self] in
                            self?.overlayController?.updateAudioLevel(level)
                        }
                    }
                } else {
                    onLevel = nil
                }
                try await audioRecorder.startCapture(onLevel: onLevel)
            } catch {
                print("[SayVoice] Audio capture failed: \(error)")
                state = .error(.microphonePermissionDenied)
            }
        }
    }

    func handleKeyUp() {
        guard state == .recording else { return }
        state = .transcribing

        Task {
            let rawSamples = await audioRecorder.stopCapture()

            // < 0.3 sec → silently return to idle
            guard rawSamples.count >= 4800 else {
                print("[SayVoice] Recording too short: \(rawSamples.count) samples")
                state = .idle
                return
            }

            // Cut the leading and trailing silence and drop recordings without
            // speech — otherwise whisper hallucinates cliches ("Thanks for the
            // subtitles…") on silence and fills in the trailing pause at the end
            // of a long dictation.
            guard let samples = SilenceTrimmer.trim(rawSamples), samples.count >= 4800 else {
                print("[SayVoice] No speech detected — skipping transcription")
                state = .idle
                return
            }

            let seconds = String(format: "%.1f", Double(samples.count) / 16000.0)
            print("[SayVoice] Captured \(rawSamples.count) samples, \(samples.count) after trim (\(seconds) sec)")

            #if DEBUG
            if let url = saveDebugWAV(samples: samples) {
                print("[SayVoice] Debug WAV saved: \(url.path)")
            }
            #endif

            do {
                let modelSize = ModelManager.ModelSize(settingsString: settingsStore.modelSize) ?? .recommended
                status.modelName = modelSize.displayName
                let prompt = settingsStore.vocabularyPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                let text = try await transcriptionEngine.transcribe(
                    samples,
                    language: settingsStore.language,
                    modelSize: modelSize,
                    vocabularyPrompt: prompt.isEmpty ? nil : prompt
                )
                print("[SayVoice] Transcription: \(text)")

                // Save to history
                let durationSec = Double(samples.count) / 16000.0
                let lang = settingsStore.language == "auto" ? nil : settingsStore.language
                let entry = TranscriptionEntry(text: text, durationSeconds: durationSec, language: lang)
                historyStore.append(entry)
                menuBarController?.historyEntries = historyStore.entries

                state = .injecting
                if settingsStore.overlayEnabled {
                    overlayController?.showResult(
                        text: text,
                        durationSeconds: durationSec,
                        onCopy: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        },
                        onShowAll: { [weak self] in
                            // A tap in the window between `.injecting` and the
                            // paste would activate this app and steal the focus
                            // from the target the text is about to go into.
                            guard let self, self.state != .injecting else { return }
                            self.overlayController?.dismiss()
                            self.menuBarController?.showHistory()
                        }
                    )
                }

                // Give the focus back to the application the dictation started in.
                await activateRecordingTarget()
                textInjector.inject(
                    text: text,
                    method: settingsStore.pasteMethod,
                    restorePasteboard: settingsStore.restorePasteboard
                )

                if settingsStore.overlayEnabled {
                    overlayController?.dismiss(after: DS.Motion.resultAutoDismiss)
                }
                state = .idle
            } catch let err as TranscriptionError {
                switch err {
                case .recordingTooShort:
                    state = .idle
                case .modelNotLoaded:
                    // `modelSize` above lives in the `do` block that just threw.
                    let modelSize = ModelManager.ModelSize(settingsString: settingsStore.modelSize) ?? .recommended
                    showSettings(section: .recognition, highlight: modelSize)
                    state = .error(.modelNotLoaded)
                case .emptyResult:
                    state = .error(.transcriptionFailed("Didn't catch anything"))
                default:
                    print("[SayVoice] Transcription error: \(err)")
                    state = .error(.transcriptionFailed(err.localizedDescription))
                }
            } catch {
                print("[SayVoice] Transcription error: \(error)")
                state = .error(.transcriptionFailed(error.localizedDescription))
            }

        }
    }

    // MARK: - Accessibility

    private func resetAccessibilityEntry() {
        permissionManager.resetAccessibilityEntry()
    }

    /// Poll every 2 sec — silently tries to start the hotkey listener.
    /// No dialogs, no console spam. When user enables Accessibility, it just works.
    private func startAccessibilityPolling() {
        accessibilityPollTask?.cancel()
        accessibilityPollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }

                do {
                    try hotkeyListener?.start(prompt: false)
                    // Success!
                    print("[SayVoice] Hotkey listener started after Accessibility grant!")
                    self.accessibilityPollTask = nil
                    self.state = .idle
                    self.continueStartupAfterAccessibility()
                    return
                } catch {
                    // Still not ready — keep polling silently
                }
            }
        }
    }

    // MARK: - Startup Continuation (after Accessibility granted)

    /// The sequential startup: Microphone → Model.
    /// Called only once Accessibility has been granted.
    private func continueStartupAfterAccessibility() {
        Task {
            // Step 2: Microphone permission
            if !permissionManager.isMicrophoneGranted {
                let granted = await permissionManager.requestMicrophone()
                if !granted {
                    print("[SayVoice] Microphone permission denied")
                }
            }

            // Step 3: Check model availability (only after mic dialog resolved)
            let modelSize = ModelManager.ModelSize(settingsString: settingsStore.modelSize) ?? .recommended
            if !modelManager.isModelAvailable(modelSize) {
                print("[SayVoice] Model \(modelSize.rawValue) not found — opening Settings → Recognition")
                showSettings(section: .recognition, highlight: modelSize)
            }
        }
    }

    // MARK: - Settings

    func showSettings(section: SettingsSection = .general, highlight: ModelManager.ModelSize? = nil) {
        settingsRouter.section = section
        settingsRouter.highlightedModel = highlight
        status.modelName = (ModelManager.ModelSize(settingsString: settingsStore.modelSize) ?? .recommended).displayName

        // Don't open multiple windows — a minimised one counts as open.
        if let existing = settingsWindow, existing.isVisible || existing.isMiniaturized {
            existing.deminiaturize(nil)
            AppWindow.present(existing)
            return
        }
        let view = SettingsView(
            settings: settingsStore, status: status, router: settingsRouter,
            downloads: modelDownloads, modelManager: modelManager,
            onHotkeyChanged: { [weak self] hotkey in
                self?.hotkeyListener?.apply(hotkey)
                self?.menuBarController?.hotkeyName = hotkey.displayName
            },
            onHotkeyModeChanged: { [weak self] isToggle in self?.hotkeyListener?.apply(isToggle: isToggle) }
        )
        let window = AppWindow.make(title: "SayVoice Settings", size: SettingsView.windowSize, content: view)
        AppWindow.present(window)
        settingsWindow = window
    }

    // MARK: - Onboarding

    private func showOnboardingWindow() {
        // A stale TCC entry survives a rebuild — the toggle reads as on while
        // AXIsProcessTrusted says no — so it is cleared before the first prompt,
        // exactly as the normal startup path does.
        if !permissionManager.isAccessibilityGranted {
            resetAccessibilityEntry()
        }

        let model = OnboardingModel(
            permissions: permissionManager, settings: settingsStore,
            modelManager: modelManager, downloads: modelDownloads,
            onFinished: { [weak self] in
                guard let self else { return }
                self.settingsStore.hasCompletedOnboarding = true
                self.removeOnboardingCloseObserver()
                self.onboardingWindow?.close()
                self.onboardingWindow = nil
                print("[SayVoice] Onboarding complete — starting normal flow")
                self.startHotkeyAndPermissions()
            }
        )
        let view = OnboardingView(
            model: model,
            onHotkeyChanged: { [weak self] hotkey in
                self?.hotkeyListener?.apply(hotkey)
                self?.menuBarController?.hotkeyName = hotkey.displayName
            },
            onHotkeyModeChanged: { [weak self] isToggle in self?.hotkeyListener?.apply(isToggle: isToggle) }
        )
        let window = AppWindow.make(title: "Welcome to SayVoice", size: OnboardingView.windowSize, content: view)
        // Closing the window from its own close button skips every step's
        // onDisappear, and the permission poll must not outlive it. Filtered by
        // `object`, so only this window counts. A second call would otherwise
        // leak the first token, so it is dropped before the new one is made.
        removeOnboardingCloseObserver()
        onboardingCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                model.stopPolling()
                self?.removeOnboardingCloseObserver()
                self?.onboardingWindow = nil
            }
        }
        AppWindow.present(window)
        onboardingWindow = window
    }

    private func removeOnboardingCloseObserver() {
        guard let token = onboardingCloseObserver else { return }
        NotificationCenter.default.removeObserver(token)
        onboardingCloseObserver = nil
    }

    // MARK: - Sound Feedback

    private func playStartSound() {
        guard settingsStore.soundFeedback else { return }
        NSSound(named: "Tink")?.play()
    }

    private func playEndSound() {
        guard settingsStore.soundFeedback else { return }
        NSSound(named: "Pop")?.play()
    }

    private func playErrorSound() {
        guard settingsStore.soundFeedback else { return }
        NSSound(named: "Basso")?.play()
    }

    /// Brings the application the dictation started in to the front.
    ///
    /// The text is inserted into the frontmost application: the pasteboard plus
    /// a synthetic Cmd+V lands wherever the system decides. So before pasting,
    /// the target has to be brought back to the front and the switch has to be
    /// waited for — otherwise the text ends up in somebody else's window.
    private func activateRecordingTarget() async {
        defer { recordingTargetApp = nil }
        guard let target = recordingTargetApp, !target.isTerminated else { return }

        let pid = target.processIdentifier
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { return }

        target.activate()
        // Wait for confirmation for up to 500 ms: activation is asynchronous,
        // and pasting before it completes is pointless.
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(50))
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { return }
        }
        print("[SayVoice] Could not bring \(target.localizedName ?? "the application") back to the front — pasting into the frontmost one")
    }

    // MARK: - State Change

    private func handleStateChange(from old: AppState, to new: AppState) {
        menuBarController?.setState(new)
        status.state = new

        switch new {
        case .idle:
            if old == .injecting {
                playEndSound()
                // Overlay result display handled by dismiss(after:) in handleKeyUp
            } else {
                overlayController?.dismiss()
            }

        case .recording:
            playStartSound()
            if settingsStore.overlayEnabled {
                overlayController?.showRecording(
                    isToggleMode: settingsStore.hotkeyIsToggle,
                    hotkeyName: settingsStore.hotkey.displayName,
                    onStop: { [weak self] in self?.handleKeyUp() }
                )
            }

        case .transcribing:
            if settingsStore.overlayEnabled {
                overlayController?.showTranscribing()
            }

        case .injecting:
            break

        case .error(let err):
            if err != .recordingTooShort {
                playErrorSound()
            }
            let msg = errorMessage(err)
            if !msg.isEmpty {
                if settingsStore.overlayEnabled {
                    // if/else rather than a ternary: the type checker cannot
                    // infer an optional labelled tuple holding a closure.
                    let action: (title: String, handler: @MainActor () -> Void)?
                    if err == .accessibilityPermissionDenied {
                        action = ("Open System Settings", { [weak self] in self?.permissionManager.openAccessibilitySettings() })
                    } else {
                        action = nil
                    }
                    overlayController?.showError(message: msg, action: action)
                }
                // Every error card is bounded, the accessibility one included:
                // it carries a button and needs longer, but it must not sit on
                // screen indefinitely swallowing clicks under its shadow.
                overlayController?.dismiss(
                    after: err == .accessibilityPermissionDenied
                        ? DS.Motion.errorWithActionAutoDismiss
                        : DS.Motion.errorAutoDismiss
                )
            }
            if err != .accessibilityPermissionDenied {
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    if case .error = self.state { self.state = .idle }
                }
            }
        }
    }

    private func errorMessage(_ error: AppError) -> String {
        switch error {
        case .microphonePermissionDenied:    return "No microphone access"
        case .accessibilityPermissionDenied: return "Enable SayVoice in Accessibility"
        case .modelNotLoaded:                return "Model not loaded"
        case .transcriptionFailed:           return "Didn't catch anything"
        case .injectionFailed:               return "Couldn't insert text"
        case .recordingTooShort:             return ""
        }
    }

    // MARK: - Debug WAV

    #if DEBUG
    /// Saves debug WAV as Int16 PCM with peak normalization.
    /// Manual WAV writing — no AVAudioFile (which crashes on Int16 buffers).
    private func saveDebugWAV(samples: [Float]) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sayvoice_debug.wav")

        // Normalize to peak = 0.95 (leave headroom)
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        let gain: Float = peak > 0.0001 ? 0.95 / peak : 1.0

        print("[SayVoice] Debug WAV: gain=\(String(format: "%.1f", gain))x (peak \(String(format: "%.4f", peak)) → 0.95)")

        // Convert Float32 [-1,1] → Int16
        let int16Samples: [Int16] = samples.map { sample in
            let amplified = sample * gain
            let clamped = max(-1.0, min(1.0, amplified))
            return Int16(clamped * Float(Int16.max))
        }

        // Write raw WAV: 44-byte RIFF header + Int16 PCM data
        let sampleRate: UInt32 = 16_000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let dataSize = UInt32(int16Samples.count * 2)
        let fileSize = 36 + dataSize

        var data = Data(capacity: 44 + Int(dataSize))

        // RIFF header
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // fmt chunk
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) }) // chunk size
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })  // PCM format
        data.append(contentsOf: withUnsafeBytes(of: channels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        let blockAlign = channels * (bitsPerSample / 8)
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

        // data chunk
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        int16Samples.withUnsafeBufferPointer { ptr in
            data.append(UnsafeBufferPointer(
                start: UnsafeRawPointer(ptr.baseAddress!).assumingMemoryBound(to: UInt8.self),
                count: Int(dataSize)
            ))
        }

        do {
            try data.write(to: url)
            return url
        } catch {
            print("[SayVoice] WAV save failed: \(error)")
            return nil
        }
    }
    #endif
}
