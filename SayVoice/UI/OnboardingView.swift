import SwiftUI

struct OnboardingView: View {
    let permissionManager: PermissionManager
    let modelManager: ModelManager
    var onComplete: () -> Void

    @State private var step: OnboardingStep = .welcome

    enum OnboardingStep {
        case welcome
        case microphone
        case accessibility
        case modelDownload
        case complete
    }

    var body: some View {
        VStack(spacing: 20) {
            switch step {
            case .welcome:
                WelcomeStepView(onNext: { step = .microphone })
            case .microphone:
                MicrophoneStepView(
                    permissionManager: permissionManager,
                    onNext: { step = .accessibility }
                )
            case .accessibility:
                AccessibilityStepView(
                    permissionManager: permissionManager,
                    onNext: {
                        step = modelManager.isModelAvailable(.recommended) ? .complete : .modelDownload
                    }
                )
            case .modelDownload:
                ModelDownloadStepView(
                    modelManager: modelManager,
                    onNext: { step = .complete }
                )
            case .complete:
                CompleteStepView(onDismiss: onComplete)
            }
        }
        .padding(24)
        .frame(width: 420, height: 300)
        // No checkInitialStep — always start from Welcome
    }
}

// MARK: - Welcome

private struct WelcomeStepView: View {
    var onNext: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("SayVoice")
                .font(.title.bold())

            Text("Голосовой ввод текста.\nНужны разрешения для работы.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Начать настройку") { onNext() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }
}

// MARK: - Microphone

private struct MicrophoneStepView: View {
    let permissionManager: PermissionManager
    var onNext: () -> Void

    @State private var granted = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Доступ к микрофону")
                .font(.title2.bold())

            Text("Нужен для записи голоса.")
                .foregroundStyle(.secondary)

            Spacer()

            if granted {
                Label("Разрешение получено", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)

                Button("Далее") { onNext() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else {
                Button("Разрешить микрофон") {
                    Task {
                        granted = await permissionManager.requestMicrophone()
                        if !granted {
                            permissionManager.openMicrophoneSettings()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Пропустить") { onNext() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .onAppear {
            granted = permissionManager.isMicrophoneGranted
        }
    }
}

// MARK: - Accessibility

private struct AccessibilityStepView: View {
    let permissionManager: PermissionManager
    var onNext: () -> Void

    @State private var granted = false
    @State private var pollTask: Task<Void, Never>?
    @State private var didResetTCC = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "accessibility")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Accessibility")
                .font(.title2.bold())

            Text("Нужен для глобального хоткея\nи вставки текста.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Spacer()

            if granted {
                Label("Разрешение получено", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)

                Button("Далее") { onNext() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else {
                HStack(spacing: 12) {
                    Button("Открыть настройки") {
                        // Reset stale TCC entry before prompting (fixes post-rebuild issue)
                        if !didResetTCC {
                            permissionManager.resetAccessibilityEntry()
                            didResetTCC = true
                        }
                        permissionManager.requestAccessibilityPrompt()
                        startPolling()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Проверить") {
                        checkAccessibility()
                    }
                    .controlSize(.large)
                }

                Button("Пропустить") { onNext() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .onAppear {
            // Reset stale TCC on appear — fresh binary after rebuild
            if !didResetTCC {
                permissionManager.resetAccessibilityEntry()
                didResetTCC = true
            }
            checkAccessibility()
            if !granted {
                startPolling()
            }
        }
        .onDisappear {
            pollTask?.cancel()
        }
    }

    private func checkAccessibility() {
        granted = permissionManager.isAccessibilityGranted
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                if permissionManager.isAccessibilityGranted {
                    granted = true
                    return
                }
            }
        }
    }
}

// MARK: - Model Download

private struct ModelDownloadStepView: View {
    let modelManager: ModelManager
    var onNext: () -> Void

    @State private var progress: Double = 0
    @State private var isDownloading = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48))
                .foregroundStyle(.purple)

            Text("Модель Whisper Small")
                .font(.title2.bold())

            Text("465 MB \u{00B7} хорошее качество RU/EN")
                .foregroundStyle(.secondary)

            Spacer()

            if isDownloading {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)

                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)

                Button("Повторить") { startDownload() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else {
                Button("Скачать модель") { startDownload() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                Button("Пропустить") { onNext() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }

    private func startDownload() {
        isDownloading = true
        error = nil
        progress = 0

        Task {
            do {
                for try await p in modelManager.downloadModel(.recommended) {
                    progress = p
                }
                onNext()
            } catch {
                self.error = error.localizedDescription
                isDownloading = false
            }
        }
    }
}

// MARK: - Complete

private struct CompleteStepView: View {
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Готово!")
                .font(.title.bold())

            Text("Зажмите Right Option (\u{2325})\nчтобы начать запись.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Начать") { onDismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }
}
