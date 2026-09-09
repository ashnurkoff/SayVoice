import XCTest
@testable import SayVoice

final class VocabularyTests: XCTestCase {

    func testTokensSplitOnCommaAndNewlineAndTrim() {
        XCTAssertEqual(TagField.tokens(from: "  API ,deployment,,\n frontend  "), ["API", "deployment", "frontend"])
    }

    func testStringRoundTripKeepsMultiWordTerms() {
        let s = "pull request, SwiftUI, Sentry"
        XCTAssertEqual(TagField.string(from: TagField.tokens(from: s)), s)
    }

    func testEmptyVocabularyYieldsOnlyThePunctuationHint() {
        XCTAssertEqual(TranscriptionEngine.initialPrompt(vocabulary: ""), TranscriptionEngine.punctuationHint)
        XCTAssertEqual(TranscriptionEngine.initialPrompt(vocabulary: nil), TranscriptionEngine.punctuationHint)
    }

    func testVocabularyIsWrappedInASentenceWithTheHintLast() {
        let p = TranscriptionEngine.initialPrompt(vocabulary: "API, Xcode")
        XCTAssertTrue(p.contains("API, Xcode."), "terms must end with a period so the model sees punctuated text")
        XCTAssertTrue(p.hasSuffix(TranscriptionEngine.punctuationHint), "hint goes last: whisper keeps the tail of an over-long prompt")
    }
}
