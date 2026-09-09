import Foundation

/// The single place an `AppError` turns into the line the user reads on the
/// overlay.
///
/// It lives outside the coordinator so the copy can be tested without building
/// one — a coordinator installs a status item, a hotkey tap and an audio engine
/// the moment it starts.
enum ErrorCopy {

    /// - Returns: the message for the error, or an empty string when the error
    ///   is not worth a card (a recording too short to transcribe).
    static func message(for error: AppError) -> String {
        switch error {
        case .microphonePermissionDenied:    return "No microphone access"
        case .accessibilityPermissionDenied: return "Enable SayVoice in Accessibility"
        case .modelNotLoaded:                return "Model not loaded"
        // The payload is the diagnosis the engine produced ("Transcription
        // timed out"); the literal is only the fallback for an empty one.
        case .transcriptionFailed(let message): return message.isEmpty ? "Didn't catch anything" : message
        case .injectionFailed:               return "Couldn't insert text"
        case .recordingTooShort:             return ""
        }
    }
}
