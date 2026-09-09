import Foundation

/// The five settings sections, in rail order.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general, recognition, dictionary, insertion, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:     return "General"
        case .recognition: return "Recognition"
        case .dictionary:  return "Dictionary"
        case .insertion:   return "Insertion"
        case .system:      return "System"
        }
    }

    var subtitle: String {
        switch self {
        case .general:     return "Hotkey, overlay and recording behaviour"
        case .recognition: return "Model and language — everything runs offline"
        case .dictionary:  return "Terms the model should spell correctly"
        case .insertion:   return "How text reaches the active app"
        case .system:      return "Startup, version and licenses"
        }
    }

    /// SF Symbol for the rail.
    var symbol: String {
        switch self {
        case .general:     return "slider.horizontal.3"
        case .recognition: return "waveform"
        case .dictionary:  return "character.book.closed"
        case .insertion:   return "text.insert"
        case .system:      return "gearshape"
        }
    }
}
