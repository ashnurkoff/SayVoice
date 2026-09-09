import Foundation

/// Where the settings window is, and what to draw attention to. Owned by the
/// coordinator so "open Recognition and highlight this model" is one call.
@MainActor @Observable
final class SettingsRouter {
    var section: SettingsSection = .general
    var highlightedModel: ModelManager.ModelSize?
}
