import Foundation

/// Defaults storage for tests.
///
/// `SettingsStore` writes through whatever `UserDefaults` it is given, and the
/// app gives it `.standard`. A test that constructed the store without an
/// argument would therefore read — and, through the vocabulary migration,
/// write — the settings of whoever runs the suite: the rendered screenshots
/// would show that person's hotkey and dictionary instead of the defaults.
enum TestDefaults {

    /// A suite of its own, named after a fresh UUID, so nothing that ran before
    /// or runs in parallel can be seen through it and the user's own settings
    /// are never touched. The domain is wiped on creation, so the store starts
    /// from the documented defaults even in the impossible case of a name
    /// colliding with something on disk.
    static func ephemeral() -> UserDefaults {
        let name = "SayVoiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
