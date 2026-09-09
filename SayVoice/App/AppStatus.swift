import Foundation

/// Read-only view of the app's state for UI that is not the coordinator —
/// the settings header pill today, the popover header in Phase 3.
@MainActor @Observable
final class AppStatus {
    var state: AppState = .idle
    /// Display name of the selected model, e.g. "Large Turbo Q5".
    var modelName: String = ""

    var pillText: String {
        guard case .idle = state, !modelName.isEmpty else { return compactText }
        return "Ready · \(modelName)"
    }

    /// The state word on its own, for hosts too narrow for the model name —
    /// the history popover header is 320 pt wide and wraps without this.
    var compactText: String {
        switch state {
        case .idle:         return "Ready"
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
