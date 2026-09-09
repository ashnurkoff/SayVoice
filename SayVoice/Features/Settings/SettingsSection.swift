import Foundation

/// The five settings sections, in rail order.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general, recognition, dictionary, insertion, system

    var id: String { rawValue }

    /// Whether the section owns the space down to the window's bottom edge.
    /// Recognition scrolls, so it does — a section that stops 28 pt short of
    /// the edge leaves a dead strip under a list that clearly continues.
    var scrollsToBottomEdge: Bool { self == .recognition }

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
