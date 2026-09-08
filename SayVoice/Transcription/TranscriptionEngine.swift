import Foundation
import WhisperSwift

actor TranscriptionEngine {
    private var transcriber: WhisperTranscriber?
    private var currentModelSize: ModelManager.ModelSize?
    private let modelManager: ModelManager
    private var idleUnloadTask: Task<Void, Never>?

    static let minimumSampleCount = 4800 // 0.3 sec @ 16kHz

    /// Beam search заметно точнее greedy, особенно на смешанной RU/EN речи.
    static let beamSize = 5

    /// Модель занимает 0.5–1.6 GB RAM — выгружаем после простоя.
    static let idleUnloadInterval: Duration = .seconds(15 * 60)

    /// Бюджет времени на транскрипцию: база на загрузку/прогрев модели плюс запас,
    /// пропорциональный длине записи. Фиксированные 30 сек рвали длинную диктовку
    /// (large-turbo + beam 5 на 60-секундной записи легко выходит за 30 сек — и вместо
    /// текста пользователь получал ошибку). Таймаут — предохранитель от зависания,
    /// а не ограничение длины: cancelAll() всё равно не прерывает синхронный вызов
    /// whisper внутри актора, поэтому потолок лучше держать с запасом.
    static let timeoutBaseSeconds = 30.0
    static let timeoutPerAudioSecond = 2.0

    static func timeoutSeconds(forSampleCount count: Int) -> Double {
        let audioSeconds = Double(count) / 16_000
        return timeoutBaseSeconds + audioSeconds * timeoutPerAudioSecond
    }

    init(modelManager: ModelManager) {
        self.modelManager = modelManager
    }

    func ensureLoaded(size: ModelManager.ModelSize) async throws {
        // Модель уже загружена с нужным размером — ничего не делаем
        if transcriber != nil && currentModelSize == size { return }

        // Выгрузить текущую модель (смена размера или первый запуск)
        transcriber = nil
        currentModelSize = nil

        let modelURL = await modelManager.modelURL(for: size)
        guard await modelManager.isModelAvailable(size) else {
            throw TranscriptionError.modelNotLoaded
        }

        do {
            transcriber = try await WhisperTranscriber(modelPath: modelURL.path)
            currentModelSize = size
            print("[SayVoice] Whisper model loaded: \(size.rawValue)")
        } catch {
            throw TranscriptionError.modelLoadFailed(modelURL)
        }
    }

    // MARK: - Initial Prompt

    /// Инструкция о пунктуации, которой заканчивается initial_prompt.
    ///
    /// У whisper нет отдельного поля «словарь»: initial_prompt — это буквально
    /// «предыдущий текст», и модель копирует его стиль. Голый список терминов через
    /// запятую, без единой точки, учит модель писать так же — речь возвращалась
    /// сплошным текстом без точек, а иногда и без запятых. Замерено на диктовке без
    /// пауз: сырой словарь — 0 точек и 0 запятых, тот же словарь внутри предложения —
    /// 3 точки и 10 запятых, как и вовсе без промпта.
    ///
    /// Инструкция идёт ПОСЛЕ словаря: при переполнении whisper берёт последние токены
    /// промпта (whisper.cpp, n_take = prompt_past.end() - n_take), то есть отрезает
    /// начало — так инструкция переживает длинный словарь.
    static let punctuationHint =
        "Расшифровка ведётся с обычной пунктуацией: точки в конце предложений, "
        + "запятые, вопросительные знаки и заглавные буквы."

    /// Собирает initial_prompt из пользовательского словаря.
    /// Пустой словарь — только инструкция о пунктуации.
    static func initialPrompt(vocabulary: String?) -> String {
        let vocab = (vocabulary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !vocab.isEmpty else { return punctuationHint }
        let terms = vocab.hasSuffix(".") ? vocab : vocab + "."
        return "В речи встречаются термины: \(terms) \(punctuationHint)"
    }

    func transcribe(
        _ samples: [Float],
        language: String = "auto",
        modelSize: ModelManager.ModelSize = .small,
        vocabularyPrompt: String? = nil
    ) async throws -> String {
        guard samples.count >= Self.minimumSampleCount else {
            throw TranscriptionError.recordingTooShort(samples.count)
        }

        idleUnloadTask?.cancel()
        defer { scheduleIdleUnload() }

        try await ensureLoaded(size: modelSize)

        guard let transcriber else {
            throw TranscriptionError.modelNotLoaded
        }

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await transcriber.transcribe(
                    samples,
                    language: language,
                    beamSize: Self.beamSize,
                    initialPrompt: Self.initialPrompt(vocabulary: vocabularyPrompt)
                )
            }
            let timeout = Self.timeoutSeconds(forSampleCount: samples.count)
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw TranscriptionError.timeout
            }

            let result = try await group.next()!
            group.cancelAll()

            if result.isEmpty {
                throw TranscriptionError.emptyResult
            }
            return result
        }
    }

    // MARK: - Idle Unload

    private func scheduleIdleUnload() {
        idleUnloadTask?.cancel()
        idleUnloadTask = Task {
            try? await Task.sleep(for: Self.idleUnloadInterval)
            guard !Task.isCancelled else { return }
            unloadModel()
        }
    }

    private func unloadModel() {
        guard transcriber != nil else { return }
        transcriber = nil
        currentModelSize = nil
        print("[SayVoice] Whisper model unloaded after \(Self.idleUnloadInterval) idle")
    }
}
