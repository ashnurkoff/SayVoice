import Foundation

/// What onboarding needs from the permission layer; `PermissionManager` conforms.
///
/// A protocol rather than the manager itself so the step machine can be tested
/// without touching TCC — granting or revoking a real permission is not
/// something a test can do.
@MainActor
protocol PermissionSource: AnyObject {
    var isMicrophoneGranted: Bool { get }
    var isAccessibilityGranted: Bool { get }
    func requestMicrophone() async -> Bool
    func openMicrophoneSettings()
    func requestAccessibilityPrompt()
    func openAccessibilitySettings()
}

/// `isAccessibilityGranted` and `requestAccessibilityPrompt` are `nonisolated`
/// on `PermissionManager`; a nonisolated member satisfies a main-actor
/// requirement, so there is nothing to write here.
extension PermissionManager: PermissionSource {}

enum OnboardingStep: Int, CaseIterable {
    case welcome, permissions, model, hotkey
}

/// Step state machine for first run. Permissions cannot be skipped — the app
/// does not work without them. Model and hotkey can.
@MainActor @Observable
final class OnboardingModel {
    let permissions: PermissionSource
    let settings: SettingsStore
    let modelManager: ModelManager
    let downloads: ModelDownloads
    private let onFinished: () -> Void

    var step: OnboardingStep = .welcome
    var microphoneGranted = false
    var accessibilityGranted = false
    private var pollTask: Task<Void, Never>?

    init(permissions: PermissionSource, settings: SettingsStore, modelManager: ModelManager,
         downloads: ModelDownloads, onFinished: @escaping () -> Void) {
        self.permissions = permissions
        self.settings = settings
        self.modelManager = modelManager
        self.downloads = downloads
        self.onFinished = onFinished
        refreshPermissions()
    }

    var canSkip: Bool { step == .model || step == .hotkey }

    var canContinue: Bool {
        step != .permissions || (microphoneGranted && accessibilityGranted)
    }

    /// The three models offered on first run (spec §5.3); the full list lives in Settings.
    static let offeredModels: [ModelManager.ModelSize] = [.turboQ5, .small, .turboQ8]

    /// The model whose download the step offers: the selected one when it is one
    /// of the three, the recommended one otherwise. Onboarding downloads a single
    /// model, so the control lives in the footer rather than in every row — three
    /// download buttons would neither fit the window nor obey the one-primary rule.
    var downloadTarget: ModelManager.ModelSize {
        guard let selected = ModelManager.ModelSize(settingsString: settings.modelSize),
              Self.offeredModels.contains(selected) else { return .recommended }
        return selected
    }

    func next() {
        guard canContinue else { return }
        advance()
    }

    func skip() {
        guard canSkip else { return }
        advance()
    }

    private func advance() {
        if let following = OnboardingStep(rawValue: step.rawValue + 1) {
            step = following
        } else {
            stopPolling()
            onFinished()
        }
    }

    // MARK: Permissions

    func refreshPermissions() {
        microphoneGranted = permissions.isMicrophoneGranted
        accessibilityGranted = permissions.isAccessibilityGranted
    }

    func requestMicrophone() {
        Task {
            microphoneGranted = await permissions.requestMicrophone()
            if !microphoneGranted { permissions.openMicrophoneSettings() }
        }
    }

    func openAccessibility() {
        permissions.requestAccessibilityPrompt()
        permissions.openAccessibilitySettings()
    }

    /// Accessibility has no callback; poll once a second while the step is visible.
    func startPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.refreshPermissions()
                if self.microphoneGranted && self.accessibilityGranted { return }
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}
