import Foundation

public final class WhisperTranscriber: Sendable {
    private let context: WhisperContext

    public init(modelPath: String) async throws {
        self.context = try WhisperContext(modelPath: modelPath)
    }

    public func transcribe(
        _ samples: [Float],
        language: String = "auto",
        beamSize: Int = 5,
        initialPrompt: String? = nil
    ) async throws -> String {
        try await context.transcribe(
            samples: samples,
            language: language,
            beamSize: beamSize,
            initialPrompt: initialPrompt
        )
    }
}
