import Foundation

enum AudioError: Error, LocalizedError {
    case engineStartFailed(Error)
    case formatConversionFailed
    case permissionDenied
    case noAudioInput
    case tapAlreadyInstalled

    var errorDescription: String? {
        switch self {
        case .engineStartFailed(let e): return "AVAudioEngine did not start: \(e.localizedDescription)"
        case .formatConversionFailed:   return "Could not convert the audio format"
        case .permissionDenied:         return "No permission to use the microphone"
        case .noAudioInput:             return "No audio input"
        case .tapAlreadyInstalled:      return "The tap is already installed"
        }
    }
}
