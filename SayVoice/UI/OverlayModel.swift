import Foundation

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
    var audioLevel: Float = 0.0
    var recordingStart: Date = Date()

    /// Режим переключателя: запись не остановится сама по отпусканию клавиши,
    /// поэтому оверлей показывает кнопку остановки и подсказку.
    var isToggleMode: Bool = false
    /// Подпись назначенного хоткея — чтобы подсказка называла конкретную клавишу.
    var hotkeyName: String = ""
    /// Остановка записи по кнопке в оверлее.
    var onStop: (@MainActor () -> Void)?

    /// Недавние уровни (~40 Гц, новые в конце) — эквалайзер берёт из них
    /// значения с задержкой по удалению от центра («рябь» от центра к краям).
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
