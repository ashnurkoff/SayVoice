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
        case .modelNotLoaded:         return "Модель не загружена"
        case .modelLoadFailed(let u): return "Не удалось загрузить модель: \(u.lastPathComponent)"
        case .inferenceError(let e):  return "Ошибка транскрипции: \(e.localizedDescription)"
        case .emptyResult:            return "Не услышал ничего"
        case .timeout:                return "Превышено время транскрипции"
        case .recordingTooShort:      return ""
        }
    }
}
