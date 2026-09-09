import Foundation

/// Read-only view of the app's state for UI that is not the coordinator —
/// the settings header pill today, the popover header in Phase 3.
@MainActor @Observable
final class AppStatus {
    var state: AppState = .idle
    /// Display name of the selected model, e.g. "Large Turbo Q5".
    var modelName: String = ""

    var pillText: String {
        switch state {
        case .idle:         return modelName.isEmpty ? "Ready" : "Ready · \(modelName)"
        case .recording:    return "Recording"
        case .transcribing: return "Transcribing…"
        case .injecting:    return "Inserting…"
        case .error:        return "Needs attention"
        }
    }

    var orbState: Orb.State {
        switch state {
        case .idle:         return .idle
        case .recording:    return .recording
        case .transcribing: return .transcribing
        case .injecting:    return .done
        case .error:        return .error
        }
    }
}
