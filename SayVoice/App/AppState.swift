import Foundation

enum AppState: Equatable {
    case idle
    case recording
    case transcribing
    case injecting
    case error(AppError)
}

enum AppError: Error, Equatable {
    case microphonePermissionDenied
    case accessibilityPermissionDenied
    case modelNotLoaded
    case transcriptionFailed(String)
    case injectionFailed
    case recordingTooShort
}
