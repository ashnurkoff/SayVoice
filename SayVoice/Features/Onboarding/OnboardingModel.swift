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
    /// Onboarding ends once. The coordinator's callback closes the window and
    /// starts the app, and a second call would start it twice.
    private var finished = false

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

    /// The model being fetched right now, whichever it is. Keyed off the whole
    /// offered list rather than off `downloadTarget`: the target follows the
    /// selection, and reading it there meant a selection change could unpin the
    /// step while the transfer it started was still running.
    var runningDownload: ModelManager.ModelSize? {
        Self.offeredModels.first {
            if case .running = downloads.state(for: $0) { return true }
            return false
        }
    }

    /// Whether a transfer is under way. The footer reads it to disable Continue
    /// and to hide "Download later": leaving mid-transfer would start the app
    /// without the model it is fetching, and Cancel is the honest way out.
    var isDownloadingTarget: Bool { runningDownload != nil }

    /// Picking a model. Ignored while a transfer runs — the download belongs to
    /// the row that started it, and a selection moved out from under it would
    /// leave the app pointing at a model nobody is fetching.
    func select(_ size: ModelManager.ModelSize) {
        guard !isDownloadingTarget else { return }
        settings.modelSize = size.settingsString
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
            guard !finished else { return }
            finished = true
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
