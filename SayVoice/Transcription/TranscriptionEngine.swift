import Foundation
import WhisperSwift

actor TranscriptionEngine {
    private var transcriber: WhisperTranscriber?
    private var currentModelSize: ModelManager.ModelSize?
    private let modelManager: ModelManager
    private var idleUnloadTask: Task<Void, Never>?

    static let minimumSampleCount = 4800 // 0.3 sec @ 16kHz

    /// Beam search is noticeably more accurate than greedy, especially on mixed RU/EN speech.
    static let beamSize = 5

    /// The model takes 0.5–1.6 GB of RAM — it is unloaded after an idle period.
    static let idleUnloadInterval: Duration = .seconds(15 * 60)

    /// The time budget for a transcription: a base for loading and warming up
    /// the model plus an allowance proportional to the length of the recording.
    /// A fixed 30 seconds tore long dictations apart (large-turbo + beam 5 on a
    /// 60-second recording easily runs past 30 seconds — and the user got an
    /// error instead of text). The timeout is a safeguard against a hang, not a
    /// limit on length: cancelAll() does not interrupt the synchronous whisper
    /// call inside the actor anyway, so the ceiling is better kept generous.
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
        // The model is already loaded at the right size — nothing to do
        if transcriber != nil && currentModelSize == size { return }

        // Unload the current model (a size change, or the first run)
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

    /// The punctuation instruction the initial_prompt ends with, in English —
    /// the wrapper used for `en` and for `auto`.
    ///
    /// whisper has no separate "dictionary" field: initial_prompt is literally
    /// "the preceding text", and the model copies its style. A bare list of
    /// terms separated by commas, without a single period, teaches the model to
    /// write the same way — speech came back as one unbroken run without
    /// periods, and sometimes without commas. Measured on a dictation with no
    /// pauses: the raw dictionary gave 0 periods and 0 commas; the same
    /// dictionary inside a sentence gave 3 periods and 10 commas, as did no
    /// prompt at all.
    ///
    /// The instruction goes AFTER the dictionary: on overflow whisper takes the
    /// last tokens of the prompt (whisper.cpp, n_take = prompt_past.end() -
    /// n_take), that is, it cuts the beginning — so the instruction survives a
    /// long dictionary.
    static let punctuationHint =
        "The transcript is written with ordinary punctuation: periods at the end of sentences, "
        + "commas, question marks and capital letters."

    /// The same instruction in Russian, used when the recognition language is
    /// `ru`. The prompt is model input, not UI: whisper's initial_prompt biases
    /// the decoder towards the language it is written in, so a Russian
    /// dictation gets a Russian wrapper — and English speech must not, which is
    /// what the EN→RU bug was.
    static let russianPunctuationHint =
        "Расшифровка ведётся с обычной пунктуацией: точки в конце предложений, "
        + "запятые, вопросительные знаки и заглавные буквы."

    /// The sentence the dictionary is wrapped in, in the language of the hint.
    private static let vocabularyLead = "The speech contains the following terms:"
    private static let russianVocabularyLead = "В речи встречаются термины:"

    /// Builds the initial_prompt from the user's dictionary.
    /// An empty dictionary yields the punctuation instruction alone.
    ///
    /// - Parameter language: the whisper language code. `ru` gets the Russian
    ///   wrapper; `en` — and `auto`, where the language is not known yet — get
    ///   the English one, because the language the prompt is written in biases
    ///   the decoder towards that language.
    static func initialPrompt(vocabulary: String?, language: String = "auto") -> String {
        let russian = language == "ru"
        let hint = russian ? russianPunctuationHint : punctuationHint
        let vocab = (vocabulary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !vocab.isEmpty else { return hint }
        let terms = vocab.hasSuffix(".") ? vocab : vocab + "."
        let lead = russian ? russianVocabularyLead : vocabularyLead
        return "\(lead) \(terms) \(hint)"
    }

    func transcribe(
        _ samples: [Float],
        language: String = "auto",
        modelSize: ModelManager.ModelSize = .recommended,
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
                    initialPrompt: Self.initialPrompt(vocabulary: vocabularyPrompt, language: language)
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
