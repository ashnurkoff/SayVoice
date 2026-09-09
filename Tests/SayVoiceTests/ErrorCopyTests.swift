import XCTest
@testable import SayVoice

/// The overlay shows whatever `ErrorCopy.message(for:)` returns. The mapping
/// used to collapse every `.transcriptionFailed` onto one literal, so a real
/// diagnosis — a timeout, a failed inference — never reached the user.
final class ErrorCopyTests: XCTestCase {

    func testAPayloadIsShownAsItIs() {
        XCTAssertEqual(ErrorCopy.message(for: .transcriptionFailed("Transcription timed out")),
                       "Transcription timed out")
        XCTAssertEqual(ErrorCopy.message(for: .transcriptionFailed(TranscriptionError.timeout.localizedDescription)),
                       "Transcription timed out",
                       "the engine's own copy must survive the trip to the overlay")
    }

    /// An empty payload is the only case that falls back to the generic line.
    func testAnEmptyPayloadFallsBackToTheGenericLine() {
        XCTAssertEqual(ErrorCopy.message(for: .transcriptionFailed("")), "Didn't catch anything")
    }

    func testEveryOtherCaseKeepsItsConstant() {
        XCTAssertEqual(ErrorCopy.message(for: .microphonePermissionDenied), "No microphone access")
        XCTAssertEqual(ErrorCopy.message(for: .accessibilityPermissionDenied), "Enable SayVoice in Accessibility")
        XCTAssertEqual(ErrorCopy.message(for: .modelNotLoaded), "Model not loaded")
        XCTAssertEqual(ErrorCopy.message(for: .injectionFailed), "Couldn't insert text")
    }

    /// A too-short recording is not an error the user needs told about: an
    /// empty message is what keeps the card off the screen.
    func testATooShortRecordingHasNoMessage() {
        XCTAssertEqual(ErrorCopy.message(for: .recordingTooShort), "")
    }
}
