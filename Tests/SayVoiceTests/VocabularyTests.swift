import XCTest
@testable import SayVoice

@MainActor
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

    // MARK: - Language of the wrapper

    /// The prompt is model input: whisper biases towards the language it is
    /// written in, so Russian dictation gets the Russian wrapper.
    func testRussianUsesTheRussianWrapper() {
        let p = TranscriptionEngine.initialPrompt(vocabulary: "API, Xcode", language: "ru")
        XCTAssertTrue(p.contains("API, Xcode."), "the terms belong in the prompt whatever the language")
        XCTAssertTrue(p.hasSuffix(TranscriptionEngine.russianPunctuationHint))
        XCTAssertEqual(TranscriptionEngine.initialPrompt(vocabulary: "", language: "ru"),
                       TranscriptionEngine.russianPunctuationHint, "an empty dictionary leaves the hint alone")
    }

    /// English, and auto — where the language is not known yet — must never be
    /// given a Russian wrapper: that is what turned English speech into Russian.
    func testEnglishAndAutoUseTheEnglishWrapper() {
        for language in ["en", "auto"] {
            let p = TranscriptionEngine.initialPrompt(vocabulary: "API, Xcode", language: language)
            XCTAssertTrue(p.hasSuffix(TranscriptionEngine.punctuationHint), language)
            XCTAssertFalse(p.contains(TranscriptionEngine.russianPunctuationHint), language)
            XCTAssertEqual(TranscriptionEngine.initialPrompt(vocabulary: nil, language: language),
                           TranscriptionEngine.punctuationHint, language)
        }
    }

    /// The wrappers are only useful if they are actually written in the language
    /// they are named for — a swapped pair still reads plausibly in the source.
    /// The lead sentence is private, so it is checked through the prompt it
    /// builds: the slice before the terms is the lead.
    func testTheRussianWrapperIsCyrillicAndTheEnglishOneIsNot() {
        XCTAssertTrue(Self.containsCyrillic(TranscriptionEngine.russianPunctuationHint))
        XCTAssertFalse(Self.containsCyrillic(TranscriptionEngine.punctuationHint))

        let ru = TranscriptionEngine.initialPrompt(vocabulary: "API, Xcode", language: "ru")
        let ruLead = String(ru[ru.startIndex..<ru.range(of: "API")!.lowerBound])
        XCTAssertTrue(Self.containsCyrillic(ruLead), "the Russian wrapper must introduce the terms in Russian")

        for language in ["en", "auto"] {
            let p = TranscriptionEngine.initialPrompt(vocabulary: "API, Xcode", language: language)
            XCTAssertFalse(Self.containsCyrillic(p), "\(language): an English prompt must hold no Cyrillic at all")
        }
    }

    /// Cyrillic and Cyrillic Supplement — enough for the two wrappers.
    private static func containsCyrillic(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x0400...0x052F).contains($0.value) }
    }
}
