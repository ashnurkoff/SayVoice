import Foundation

public enum WhisperError: Error, LocalizedError {
    case modelLoadFailed(String)
    case transcriptionFailed
    case invalidSampleCount(Int)
    case contextIsNil

    public var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let path): return "Не удалось загрузить модель: \(path)"
        case .transcriptionFailed:       return "Транскрипция не удалась"
        case .invalidSampleCount(let n): return "Некорректное количество сэмплов: \(n)"
        case .contextIsNil:              return "Whisper context не инициализирован"
        }
    }
}
