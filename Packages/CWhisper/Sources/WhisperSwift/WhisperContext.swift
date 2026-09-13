import Foundation
import CWhisper

public actor WhisperContext {
    private var ctx: OpaquePointer?

    public init(modelPath: String) throws {
        guard let context = whisper_bridge_init(modelPath) else {
            throw WhisperError.modelLoadFailed(modelPath)
        }
        self.ctx = context
    }

    public func transcribe(
        samples: [Float],
        language: String = "auto",
        beamSize: Int = 5,
        initialPrompt: String? = nil
    ) throws -> String {
        guard let ctx else {
            throw WhisperError.contextIsNil
        }

        guard !samples.isEmpty else {
            throw WhisperError.invalidSampleCount(0)
        }

        // Пустой промпт → nullptr (bridge также проверяет пустую строку)
        let prompt = (initialPrompt?.isEmpty == false) ? initialPrompt! : ""

        let rawResult: UnsafeMutablePointer<CChar>? = language.withCString { langPtr in
            prompt.withCString { promptPtr in
                let params = SayVoiceWhisperParams(
                    n_threads: Int32(max(1, ProcessInfo.processInfo.processorCount - 2)),
                    translate: false,
                    // ВАЖНО: timestamp-токены обязаны быть включены (no_timestamps = false).
                    // Whisper decoder'ит аудио окнами по 30 сек и сдвигает окно на конец
                    // последнего распознанного сегмента (whisper.cpp: seek += seek_delta).
                    // При no_timestamps = true сегментных таймстемпов нет, и seek_delta
                    // принудительно = 30 сек (whisper.cpp:5893) — окно прыгает целиком,
                    // а фраза, попавшая на стык окон, не декодируется ни в одном из них:
                    // на диктовке длиннее 30 сек пропадали несколько слов/предложение.
                    // Сами таймстемпы в текст не попадают: bridge собирает сегменты через
                    // whisper_full_get_segment_text, а при print_special = false спец-токены
                    // (включая timestamp) отфильтрованы (whisper.cpp:6124).
                    no_timestamps: false,
                    temperature: 0.0,
                    language: langPtr,
                    beam_size: Int32(beamSize),
                    initial_prompt: promptPtr
                )

                return samples.withUnsafeBufferPointer { ptr in
                    whisper_bridge_transcribe(
                        ctx,
                        ptr.baseAddress,
                        Int32(samples.count),
                        params
                    )
                }
            }
        }

        guard let rawResult else {
            throw WhisperError.transcriptionFailed
        }

        defer { whisper_bridge_free_string(rawResult) }
        return String(cString: rawResult)
    }

    /// The language whisper hears in the first 30 seconds, as a whisper code
    /// ("ru", "en", …), or nil when it cannot tell.
    public func detectLanguage(samples: [Float]) -> String? {
        guard let ctx, !samples.isEmpty else { return nil }
        let threads = Int32(max(1, ProcessInfo.processInfo.processorCount - 2))
        let code: UnsafePointer<CChar>? = samples.withUnsafeBufferPointer { ptr in
            whisper_bridge_detect_language(ctx, ptr.baseAddress, Int32(samples.count), threads)
        }
        guard let code else { return nil }
        return String(cString: code)
    }

    deinit {
        if let ctx {
            whisper_bridge_free(ctx)
        }
    }
}
