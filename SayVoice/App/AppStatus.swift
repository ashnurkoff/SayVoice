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

    /// Colour of the status pill's dot: the classic status light — green when
    /// ready, red while recording, the accent while work is in flight, amber
    /// when something needs attention. Deliberately not `orbState`: the orb is
    /// the brand mark and stays accent at idle in the overlay and the menu bar,
    /// while a pill that glows brand-purple for "Ready" says nothing at all.
    var pillTint: DSColor {
        switch state {
        case .idle:                     return DS.Colors.ok
        case .recording:                return DS.Colors.rec
        case .transcribing, .injecting: return DS.Colors.accent
        case .error:                    return DS.Colors.warn
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
