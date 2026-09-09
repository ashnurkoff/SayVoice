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
    private var downloadWindow: NSWindow?
    private var settingsWindow: NSWindow?

    /// Приложение, в котором началась диктовка. Текст уходит именно туда, а не туда,
    /// где пользователь оказался к моменту окончания: в режиме переключателя запись
    /// длится долго, и за это время легко переключиться на другое окно.
    private var recordingTargetApp: NSRunningApplication?
    private var onboardingWindow: NSWindow?

    func start() {
        menuBarController = MenuBarController()
        menuBarController?.onQuit = { NSApp.terminate(nil) }
        menuBarController?.onDownloadModel = { [weak self] in self?.showModelDownloadWindow() }
        menuBarController?.onShowSettings = { [weak self] in self?.showSettingsWindow() }
        menuBarController?.onClearHistory = { [weak self] in
            self?.historyStore.clear()
            self?.menuBarController?.historyEntries = []
        }
        menuBarController?.onPopoverWillShow = { [weak self] in
            guard let self else { return }
            self.menuBarController?.historyEntries = self.historyStore.recent()
        }

        overlayController = OverlayWindowController()

        hotkeyListener = HotkeyListener(coordinator: self)
        hotkeyListener?.apply(settingsStore.hotkey)
        hotkeyListener?.apply(isToggle: settingsStore.hotkeyIsToggle)

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
                // continueStartupAfterAccessibility() вызовется из polling success
            }
        }
    }

    /// Одно нажатие в режиме переключателя: начинает или останавливает запись.
    func handleHotkeyToggle() {
        switch state {
        case .idle:      handleKeyDown()
        case .recording: handleKeyUp()
        default:         break   // идёт расшифровка или вставка — нажатие игнорируем
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

            // Обрезаем ведущую/хвостовую тишину и отсекаем записи без речи — иначе
            // whisper галлюцинирует клише («Спасибо за субтитры…») на тишине и
            // «дописывает» хвостовую паузу в конце длинной диктовки.
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
                let modelSize = ModelManager.ModelSize(settingsString: settingsStore.modelSize) ?? .small
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
                menuBarController?.historyEntries = historyStore.recent()

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
                            self?.overlayController?.dismiss()
                            self?.menuBarController?.showHistory()
                        }
                    )
                }

                // Возвращаем активность приложению, где началась диктовка.
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
                    showModelDownloadWindow()
                    state = .error(.modelNotLoaded)
                case .emptyResult:
                    state = .error(.transcriptionFailed("Не услышал ничего"))
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

    /// Последовательный startup: Microphone → Model.
    /// Вызывается только после того, как Accessibility уже granted.
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
            let modelSize = ModelManager.ModelSize(settingsString: settingsStore.modelSize) ?? .small
            if !modelManager.isModelAvailable(modelSize) {
                print("[SayVoice] Model \(modelSize.rawValue) not found — showing download window")
                showModelDownloadWindow()
            }
        }
    }

    // MARK: - Model Download

    private func showModelDownloadWindow() {
        // Don't open multiple windows
        if let existing = downloadWindow, existing.isVisible { return }

        let selectedModel = ModelManager.ModelSize(settingsString: settingsStore.modelSize) ?? .small
        let view = ModelDownloadView(modelManager: modelManager, modelSize: selectedModel) { [weak self] in
            guard let self else { return }
            print("[SayVoice] Model download complete")
            self.downloadWindow?.close()
            self.downloadWindow = nil
            if case .error(.modelNotLoaded) = self.state {
                self.state = .idle
            }
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "SayVoice"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.downloadWindow = window
    }

    // MARK: - Settings

    private func showSettingsWindow() {
        // Don't open multiple windows
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(
            settings: settingsStore,
            modelManager: modelManager,
            onHotkeyChanged: { [weak self] hotkey in self?.hotkeyListener?.apply(hotkey) },
            onHotkeyModeChanged: { [weak self] isToggle in self?.hotkeyListener?.apply(isToggle: isToggle) }
        )

        let window = NSWindow(
            // Размер должен совпадать с .frame в SettingsView — иначе окно обрежет содержимое.
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 760),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "SayVoice — Настройки"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.settingsWindow = window
    }

    // MARK: - Onboarding

    private func showOnboardingWindow() {
        let view = OnboardingView(
            permissionManager: permissionManager,
            modelManager: modelManager,
            onComplete: { [weak self] in
                guard let self else { return }
                self.settingsStore.hasCompletedOnboarding = true
                self.onboardingWindow?.close()
                self.onboardingWindow = nil
                print("[SayVoice] Onboarding complete — starting normal flow")
                self.startHotkeyAndPermissions()
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "SayVoice — Настройка"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.onboardingWindow = window
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

    /// Делает фронтальным приложение, в котором началась диктовка.
    ///
    /// Вставка текста идёт во фронтальное приложение: буфер обмена с синтетическим
    /// Cmd+V попадает туда, куда система считает нужным. Поэтому перед вставкой цель
    /// нужно вернуть на передний план и дождаться, пока переключение действительно
    /// произошло — иначе текст уедет в чужое окно.
    private func activateRecordingTarget() async {
        defer { recordingTargetApp = nil }
        guard let target = recordingTargetApp, !target.isTerminated else { return }

        let pid = target.processIdentifier
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { return }

        target.activate()
        // Ждём подтверждения до 500 мс: активация асинхронная, и вставлять
        // до её завершения бессмысленно.
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(50))
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { return }
        }
        print("[SayVoice] Не удалось вернуть активность \(target.localizedName ?? "приложению") — вставляем во фронтальное")
    }

    // MARK: - State Change

    private func handleStateChange(from old: AppState, to new: AppState) {
        menuBarController?.setState(new)

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
