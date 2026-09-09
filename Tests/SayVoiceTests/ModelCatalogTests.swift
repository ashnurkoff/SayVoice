import XCTest
@testable import SayVoice

final class ModelCatalogTests: XCTestCase {

    func testEveryModelHasAQualityStepInRange() {
        for m in ModelManager.ModelSize.allCases {
            XCTAssertTrue((1...5).contains(m.qualitySteps), "\(m) has \(m.qualitySteps)")
        }
    }

    func testQualityIsMonotonicAcrossTheCatalogue() {
        let steps = ModelManager.ModelSize.allCases.map(\.qualitySteps)
        XCTAssertEqual(steps, steps.sorted(), "catalogue is listed from lightest to best")
    }

    func testRecommendedIsTurboQ5AndIsTheStoreDefault() {
        XCTAssertEqual(ModelManager.ModelSize.recommended, .turboQ5)
        XCTAssertEqual(ModelManager.ModelSize(settingsString: "large-v3-turbo-q5"), .turboQ5)
        XCTAssertEqual(ModelManager.ModelSize.recommended.settingsString, "large-v3-turbo-q5")
    }

    func testProgressFractionIsClampedAndSafe() {
        XCTAssertEqual(ModelDownloadProgress(bytesReceived: 50, totalBytes: 200).fraction, 0.25)
        XCTAssertEqual(ModelDownloadProgress(bytesReceived: 10, totalBytes: 0).fraction, 0, "unknown total → 0, never NaN")
        XCTAssertEqual(ModelDownloadProgress(bytesReceived: 300, totalBytes: 200).fraction, 1)
    }

    @MainActor
    func testDownloadStreamStopsWhenConsumerIsCancelled() async {
        // A cancelled consumer must see the stream end promptly — as nil
        // (AsyncThrowingStream ends on cancellation) or as an error — instead
        // of hanging on the connection until the transfer finishes.
        let manager = ModelManager()
        let finalURL = manager.modelURL(for: .base)
        let existedBefore = FileManager.default.fileExists(atPath: finalURL.path)
        let task = Task { () -> String in
            var count = 0
            do {
                for try await _ in manager.downloadModelProgress(.base) { count += 1 }
                return "ended after \(count) chunk(s)"
            } catch {
                return "ended with \(type(of: error))"
            }
        }
        try? await Task.sleep(for: .milliseconds(150))
        let cancelledAt = Date()
        task.cancel()
        let result = await task.value
        let waited = Date().timeIntervalSince(cancelledAt)
        XCTAssertLessThan(waited, 3, "stream kept running \(waited)s after cancel (\(result))")

        // Cancelling must not fall through to the finalise-and-move step: a
        // truncated ggml-base.bin would be reported as a usable model.
        if !existedBefore {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: finalURL.path),
                "a cancelled download published a model file at \(finalURL.path) (\(result))"
            )
        }
    }
}
