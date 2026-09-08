import Foundation

enum AudioError: Error, LocalizedError {
    case engineStartFailed(Error)
    case formatConversionFailed
    case permissionDenied
    case noAudioInput
    case tapAlreadyInstalled

    var errorDescription: String? {
        switch self {
        case .engineStartFailed(let e): return "AVAudioEngine не запустился: \(e.localizedDescription)"
        case .formatConversionFailed:   return "Не удалось конвертировать аудио формат"
        case .permissionDenied:         return "Нет разрешения на использование микрофона"
        case .noAudioInput:             return "Нет аудио-входа"
        case .tapAlreadyInstalled:      return "Tap уже установлен"
        }
    }
}
