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
        // The only test that touches the network: it needs a real transfer to
        // prove a cancelled consumer stops it. Everything else runs offline.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = ModelManager(modelsDirectory: directory)
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

    // MARK: - HTTP status

    /// A 404 is a perfectly successful transfer whose body is an error page.
    /// Moving that into place would publish it as a model, and whisper would
    /// then fail to load a file the app reports as downloaded.
    @MainActor
    func testAnErrorStatusFailsTheDownloadAndLeavesNothingOnDisk() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = ModelManager(modelsDirectory: directory,
                                   sessionConfiguration: Self.configuration(with: NotFoundURLProtocol.self))

        var thrown: Error?
        do {
            for try await _ in manager.downloadModelProgress(.base) {}
        } catch {
            thrown = error
        }

        XCTAssertNotNil(thrown, "a 404 must end the stream with an error, not with a model")
        XCTAssertFalse(FileManager.default.fileExists(atPath: manager.modelURL(for: .base).path),
                       "the error page was published as a model file")
    }

    /// The counterpart: a 200 still finishes and publishes the file, so the
    /// status check cannot be satisfied by rejecting everything.
    @MainActor
    func testASuccessfulStatusPublishesTheFile() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = ModelManager(modelsDirectory: directory,
                                   sessionConfiguration: Self.configuration(with: OKURLProtocol.self))

        do {
            for try await _ in manager.downloadModelProgress(.base) {}
        } catch {
            return XCTFail("a 200 must not throw: \(error)")
        }
        XCTAssertTrue(manager.isModelAvailable(.base), "a completed transfer must leave the file in place")
    }

    private static func configuration(with stub: URLProtocol.Type) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [stub]
        return configuration
    }

    // MARK: - URL protocol stubs

    /// Answers every request with a canned response, so the download path can be
    /// exercised without a network.
    class StubURLProtocol: URLProtocol {
        /// Status of the canned response; the body is a short stand-in payload.
        class var status: Int { 200 }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func stopLoading() {}

        override func startLoading() {
            let body = Data("stub payload".utf8)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Length": String(body.count)]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    final class NotFoundURLProtocol: StubURLProtocol {
        override class var status: Int { 404 }
    }

    final class OKURLProtocol: StubURLProtocol {
        override class var status: Int { 200 }
    }
}
