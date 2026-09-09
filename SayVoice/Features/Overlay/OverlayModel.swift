import Foundation

/// State of the recording overlay. Owned by `OverlayWindowController`,
/// observed by `OverlayView`.
@MainActor @Observable
final class OverlayModel {
    enum DisplayState: Equatable {
        case hidden
        case recording
        case transcribing
        case result
        case error
    }

    var displayState: DisplayState = .hidden
    var message: String = ""
    var audioLevel: Float = 0
    var recordingStart: Date = Date()

    /// Toggle mode: the recording does not stop on key release, so the
    /// overlay shows a Stop button and a hint.
    var isToggleMode: Bool = false
    /// Display name of the configured hotkey, for the hint text.
    var hotkeyName: String = ""
    var onStop: (@MainActor () -> Void)?

    /// Result state: length of the recording and the two actions.
    var durationSeconds: Double = 0
    var onCopy: (@MainActor () -> Void)?
    var onShowAll: (@MainActor () -> Void)?

    /// Error state: optional action such as "Open System Settings".
    var errorAction: (title: String, handler: @MainActor () -> Void)?

    /// Pointer is over the panel — auto-dismiss waits while this is true.
    var isHovered: Bool = false

    /// Recent levels (~40 Hz, newest last) — the waveform reads them with a
    /// per-bar delay so the wave ripples from the centre.
    private(set) var levelHistory: [Float] = []

    private static let historyLimit = 64

    func appendLevel(_ level: Float) {
        audioLevel = level
        levelHistory.append(level)
        if levelHistory.count > Self.historyLimit {
            levelHistory.removeFirst(levelHistory.count - Self.historyLimit)
        }
    }

    func resetLevels() {
        levelHistory = []
        audioLevel = 0
    }
}
