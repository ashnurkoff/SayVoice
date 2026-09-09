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
    case welcome, permissions, model, hotkey, done
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

    /// Permissions cannot be skipped, and neither can the closing step — there
    /// is nothing on it to decide. The model step also locks while its download
    /// runs, so "Download later" cannot abandon a transfer that is under way.
    var canSkip: Bool {
        switch step {
        case .model:  return !isDownloadingTarget
        case .hotkey: return true
        default:      return false
        }
    }

    var canContinue: Bool {
        switch step {
        case .permissions: return microphoneGranted && accessibilityGranted
        case .model:       return !isDownloadingTarget
        default:           return true
        }
    }

    /// The models offered on first run (spec §5.3): the whole catalogue, in the
    /// same order as Settings → Recognition. The subset of three the step used
    /// to show hid the two the owner most wanted to compare.
    static let offeredModels: [ModelManager.ModelSize] = ModelManager.ModelSize.allCases

    /// The model whose download the step offers: the selected one, or the
    /// recommended one when the stored string names nothing. Onboarding
    /// downloads a single model, so the control lives in the footer rather than
    /// in every row — five download buttons would neither fit the window nor
    /// obey the one-primary rule.
    var downloadTarget: ModelManager.ModelSize {
        ModelManager.ModelSize(settingsString: settings.modelSize) ?? .recommended
    }

    /// Whether the model the step offers is being fetched right now. The footer
    /// reads it to disable Continue and to hide "Download later": leaving
    /// mid-transfer would start the app without the model it is fetching, and
    /// Cancel is the honest way out.
    var isDownloadingTarget: Bool {
        if case .running = downloads.state(for: downloadTarget) { return true }
        return false
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

    /// Whether the permission poll is running. Read by the tests that check
    /// which window closing is allowed to stop it.
    var isPolling: Bool { pollTask != nil }
}
