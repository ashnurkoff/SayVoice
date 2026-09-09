import CoreGraphics
import Foundation
import Observation
import ServiceManagement

/// The central store of the application settings.
/// Uses `@Observable` (macOS 14+) so SwiftUI updates reactively.
/// Every property saves itself to UserDefaults through `didSet`.
@MainActor @Observable
final class SettingsStore {

    /// The storage the settings are written to. `.standard` by default; tests
    /// pass a suite of their own so the user's settings are left alone.
    private let defaults: UserDefaults

    // MARK: - Properties

    /// The virtual key code of the recording hotkey. 61 (Right Option) by default.
    var hotkeyCode: Int {
        didSet { defaults.set(hotkeyCode, forKey: SettingsKeys.hotkeyCode) }
    }

    /// The hotkey modifiers — the raw CGEventFlags mask. For a modifier hotkey
    /// this is its own mask (see Hotkey).
    var hotkeyFlags: Int {
        didSet { defaults.set(hotkeyFlags, forKey: SettingsKeys.hotkeyFlags) }
    }

    /// The mouse button assigned to recording; -1 means a keyboard hotkey.
    var hotkeyMouseButton: Int {
        didSet { defaults.set(hotkeyMouseButton, forKey: SettingsKeys.hotkeyMouseButton) }
    }

    /// How the hotkey works: "hold" — the recording runs while the key is held;
    /// "toggle" — one press starts it, another press stops it.
    ///
    /// The toggle is not there for convenience but because some buttons do not
    /// report a hold at all: utilities such as Logi Options+ send a short tap
    /// (measured: 12 ms) no matter how long the button is held.
    var hotkeyMode: String {
        didSet { defaults.set(hotkeyMode, forKey: SettingsKeys.hotkeyMode) }
    }

    var hotkeyIsToggle: Bool { hotkeyMode == "toggle" }

    /// The hotkey as a whole. It decomposes into the three stored fields, so
    /// the UI and the listener work with one value rather than a combination.
    var hotkey: Hotkey {
        get {
            Hotkey(
                keyCode: CGKeyCode(hotkeyCode),
                flags: UInt64(hotkeyFlags),
                mouseButton: hotkeyMouseButton >= 0 ? hotkeyMouseButton : nil
            )
        }
        set {
            hotkeyCode = Int(newValue.keyCode)
            hotkeyFlags = Int(newValue.flags)
            hotkeyMouseButton = newValue.mouseButton ?? -1
        }
    }

    /// The Whisper model size: "tiny", "base", "small".
    var modelSize: String {
        didSet { defaults.set(modelSize, forKey: SettingsKeys.modelSize) }
    }

    /// The recognition language: "auto" or a whisper language code ("ru", "en", "de", …).
    var language: String {
        didSet { defaults.set(language, forKey: SettingsKeys.language) }
    }

    /// Show the overlay while recording and transcribing.
    var overlayEnabled: Bool {
        didSet { defaults.set(overlayEnabled, forKey: SettingsKeys.overlayEnabled) }
    }

    /// Put the previous clipboard contents back after the dictation is pasted.
    /// true — the clipboard is unharmed, but Cmd+V pastes whatever was copied
    /// before. false — the dictated text stays on the clipboard and the previous
    /// contents are lost.
    var restorePasteboard: Bool {
        didSet { defaults.set(restorePasteboard, forKey: SettingsKeys.restorePasteboard) }
    }

    /// Play sounds when the recording starts and stops.
    var soundFeedback: Bool {
        didSet { defaults.set(soundFeedback, forKey: SettingsKeys.soundFeedback) }
    }

    /// The text insertion method: "pasteboard" (Cmd+V) or "ax" (Accessibility API).
    var pasteMethod: String {
        didSet { defaults.set(pasteMethod, forKey: SettingsKeys.pasteMethod) }
    }

    /// Launch the application at login.
    var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: SettingsKeys.launchAtLogin)
            updateLaunchAtLogin(enabled: launchAtLogin)
        }
    }

    /// Whether the user has been through onboarding.
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: SettingsKeys.hasCompletedOnboarding) }
    }

    /// The dictionary/context for Whisper (initial_prompt): it helps recognise
    /// mixed RU/EN speech and specific terms more accurately. An empty string
    /// means no prompt.
    var vocabularyPrompt: String {
        didSet { defaults.set(vocabularyPrompt, forKey: SettingsKeys.vocabularyPrompt) }
    }

    /// The default prompt: a bare list of IT terms in the Latin alphabet.
    /// `initial_prompt` in whisper is a sample of vocabulary and style that
    /// conditions the decoder. A list of terms hints at their spelling WITHOUT
    /// imposing a language on the whole dictation.
    ///
    /// What used to be here was a Russian sentence ("Dictation in Russian…"),
    /// which pulled the decoder towards Russian tokens and, in auto mode,
    /// "translated" English speech into Russian (the EN→RU bug). See
    /// legacyRussianVocabularyPrompt.
    static let defaultVocabularyPrompt =
        "API, deployment, frontend, backend, commit, pull request, feature, bug, SwiftUI, Xcode, TypeScript, React, endpoint, refactor, staging, production"

    /// The old default: a Russian sentence. It pulled whisper towards Russian
    /// and broke English dictation. Kept only to migrate a stored value — when
    /// UserDefaults holds exactly this string, it has to be replaced with the
    /// new default.
    static let legacyRussianVocabularyPrompt =
        "Диктовка на русском языке с английскими словами и IT-терминами: API, deployment, frontend, backend, commit, pull request, feature, bug, SwiftUI, Xcode."

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let d = defaults

        // Int: object(forKey:) as? Int ?? default — otherwise integer(forKey:) returns 0 for a missing key
        self.hotkeyCode  = d.object(forKey: SettingsKeys.hotkeyCode) as? Int ?? Int(Hotkey.default.keyCode)
        self.hotkeyFlags = d.object(forKey: SettingsKeys.hotkeyFlags) as? Int ?? Int(Hotkey.default.flags)
        self.hotkeyMouseButton = d.object(forKey: SettingsKeys.hotkeyMouseButton) as? Int ?? -1
        self.hotkeyMode = d.string(forKey: SettingsKeys.hotkeyMode) ?? "hold"

        // String: string(forKey:) ?? default
        self.modelSize   = d.string(forKey: SettingsKeys.modelSize) ?? ModelManager.ModelSize.recommended.settingsString
        self.language    = d.string(forKey: SettingsKeys.language) ?? "auto"
        self.pasteMethod = d.string(forKey: SettingsKeys.pasteMethod) ?? "pasteboard"

        // Bool defaulting to true: object(forKey:) as? Bool ?? true
        // (bool(forKey:) returns false for a missing key!)
        self.overlayEnabled = d.object(forKey: SettingsKeys.overlayEnabled) as? Bool ?? true
        self.soundFeedback  = d.object(forKey: SettingsKeys.soundFeedback) as? Bool ?? true
        self.restorePasteboard = d.object(forKey: SettingsKeys.restorePasteboard) as? Bool ?? true

        // Bool defaulting to false: bool(forKey:) is safe
        self.launchAtLogin          = d.bool(forKey: SettingsKeys.launchAtLogin)
        self.hasCompletedOnboarding = d.bool(forKey: SettingsKeys.hasCompletedOnboarding)

        // Migration: empty, or exactly the old Russian prompt → the new neutral
        // default. A prompt the user wrote is left alone.
        let storedPrompt = d.string(forKey: SettingsKeys.vocabularyPrompt)
        if storedPrompt == nil || storedPrompt == Self.legacyRussianVocabularyPrompt {
            self.vocabularyPrompt = Self.defaultVocabularyPrompt
            d.set(Self.defaultVocabularyPrompt, forKey: SettingsKeys.vocabularyPrompt)
        } else {
            self.vocabularyPrompt = storedPrompt!
        }
    }

    // MARK: - Launch at Login

    private func updateLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                print("[SayVoice] Launch at login: registered")
            } else {
                try SMAppService.mainApp.unregister()
                print("[SayVoice] Launch at login: unregistered")
            }
        } catch {
            print("[SayVoice] Launch at login failed: \(error)")
        }
    }
}
