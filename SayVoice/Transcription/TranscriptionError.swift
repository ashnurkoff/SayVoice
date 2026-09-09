import Foundation

enum TranscriptionError: Error, LocalizedError {
    case modelNotLoaded
    case modelLoadFailed(URL)
    case inferenceError(Error)
    case emptyResult
    case timeout
    case recordingTooShort(Int)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:         return "The model is not loaded"
        case .modelLoadFailed(let u): return "Could not load the model: \(u.lastPathComponent)"
        case .inferenceError(let e):  return "Transcription failed: \(e.localizedDescription)"
        case .emptyResult:            return "Didn't catch anything"
        case .timeout:                return "Transcription timed out"
        case .recordingTooShort:      return ""
        }
    }
}
