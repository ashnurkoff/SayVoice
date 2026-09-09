import Foundation

/// UserDefaults keys for the application settings.
/// The `sv_` prefix guarantees there are no collisions.
enum SettingsKeys {
    static let hotkeyCode             = "sv_hotkey_code"
    static let hotkeyFlags            = "sv_hotkey_flags"
    static let hotkeyMouseButton      = "sv_hotkey_mouse_button"
    static let hotkeyMode             = "sv_hotkey_mode"
    static let modelSize              = "sv_model_size"
    static let language               = "sv_language"
    static let overlayEnabled         = "sv_overlay_enabled"
    static let soundFeedback          = "sv_sound_feedback"
    static let pasteMethod            = "sv_paste_method"
    static let restorePasteboard      = "sv_restore_pasteboard"
    static let launchAtLogin          = "sv_launch_at_login"
    static let hasCompletedOnboarding = "sv_onboarding_done"
    static let vocabularyPrompt       = "sv_vocabulary_prompt"
}
