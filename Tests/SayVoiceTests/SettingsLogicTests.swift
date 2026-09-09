import AppKit
import SwiftUI
import XCTest
@testable import SayVoice

@MainActor
final class SettingsLogicTests: XCTestCase {

    func testStatusPillText() {
        let s = AppStatus()
        s.modelName = "Large Turbo Q5"
        s.state = .idle;          XCTAssertEqual(s.pillText, "Ready · Large Turbo Q5")
        s.state = .recording;     XCTAssertEqual(s.pillText, "Recording")
        s.state = .transcribing;  XCTAssertEqual(s.pillText, "Transcribing…")
        s.state = .injecting;     XCTAssertEqual(s.pillText, "Inserting…")
        s.state = .error(.modelNotLoaded); XCTAssertEqual(s.pillText, "Needs attention")

        // No model chosen yet: no dangling separator.
        s.modelName = ""
        s.state = .idle; XCTAssertEqual(s.pillText, "Ready")
    }

    func testSectionsAreOrderedAsSpecified() {
        XCTAssertEqual(SettingsSection.allCases.map(\.rawValue), ["general", "recognition", "dictionary", "insertion", "system"])
        for s in SettingsSection.allCases {
            XCTAssertFalse(s.title.isEmpty); XCTAssertFalse(s.subtitle.isEmpty); XCTAssertFalse(s.symbol.isEmpty)
        }
    }

    func testDownloadsReportNilForModelsOnDiskAndIdleOtherwise() {
        let manager = ModelManager(modelsDirectory: temporaryModelsDirectory())
        let onDisk = ModelManager.ModelSize.base
        XCTAssertTrue(FileManager.default.createFile(atPath: manager.modelURL(for: onDisk).path, contents: Data("stub".utf8)))
        let downloads = ModelDownloads(modelManager: manager)

        XCTAssertNil(downloads.state(for: onDisk), "a model on disk has nothing to offer")
        for m in ModelManager.ModelSize.allCases where m != onDisk {
            XCTAssertEqual(downloads.state(for: m), .idle, "\(m)")
        }
    }

    // MARK: - ModelDownloads state machine

    func testDownloadStartReportsRunningAndFollowsTheStream() async {
        let source = StubProgressSource()
        let downloads = makeDownloads(source: source, available: false)

        downloads.start(.base)
        XCTAssertEqual(downloads.state(for: .base), .running(fraction: 0, bytesPerSecond: nil, secondsLeft: nil))

        await waitUntil({ source.continuation != nil }, "the task never asked for a stream")
        source.continuation?.yield(ModelDownloadProgress(bytesReceived: 25, totalBytes: 100))
        await waitUntil({ Self.fraction(downloads.state(for: .base)) == 0.25 }, "first progress not observed")

        // Past the 100 ms write throttle, so the second sample is not coalesced.
        try? await Task.sleep(for: .milliseconds(150))
        source.continuation?.yield(ModelDownloadProgress(bytesReceived: 50, totalBytes: 100))
        await waitUntil({ Self.fraction(downloads.state(for: .base)) == 0.5 }, "second progress not observed")
    }

    func testCancelIsImmediateAndFreesTheTaskSlot() async {
        let source = StubProgressSource()
        let downloads = makeDownloads(source: source, available: false)

        downloads.start(.base)
        await waitUntil({ source.continuation != nil }, "the task never asked for a stream")
        source.continuation?.yield(ModelDownloadProgress(bytesReceived: 10, totalBytes: 100))
        await waitUntil({ Self.fraction(downloads.state(for: .base)) == 0.1 }, "progress not observed")

        downloads.cancel(.base)
        XCTAssertEqual(downloads.state(for: .base), .idle, "cancel must read as idle at once, not after the stream unwinds")

        await waitUntil({
            downloads.start(.base)
            if case .running = downloads.storedState(for: .base) { return true }
            return false
        }, "the task slot was never freed, so the model could not be downloaded again")
    }

    /// The slot must be free the instant Cancel returns, not once the transfer
    /// unwinds: the user's next click is Retry, and it lands synchronously.
    func testCancelFreesTheTaskSlotSynchronously() async {
        let source = StubProgressSource()
        let downloads = makeDownloads(source: source, available: false)

        downloads.start(.base)
        await waitUntil({ source.continuation != nil }, "the task never asked for a stream")
        source.continuation?.yield(ModelDownloadProgress(bytesReceived: 10, totalBytes: 100))
        await waitUntil({ Self.fraction(downloads.state(for: .base)) == 0.1 }, "progress not observed")

        downloads.cancel(.base)
        downloads.start(.base)
        guard case .running = downloads.storedState(for: .base) else {
            return XCTFail("a start right after cancel must run at once, got \(String(describing: downloads.storedState(for: .base)))")
        }

        // The cancelled transfer settles a moment later; its outcome belongs to
        // a run that is over and must not overwrite the one now in flight.
        try? await Task.sleep(for: .milliseconds(120))
        guard case .running = downloads.storedState(for: .base) else {
            return XCTFail("the cancelled run stomped the new one: \(String(describing: downloads.storedState(for: .base)))")
        }
    }

    func testStreamEndWithTheFileOnDiskIsDoneAndReportsCompletionOnce() async {
        let source = StubProgressSource()
        let downloads = makeDownloads(source: source, available: true)
        var completions: [ModelManager.ModelSize] = []
        downloads.onCompleted = { completions.append($0) }

        downloads.start(.base)
        await waitUntil({ source.continuation != nil }, "the task never asked for a stream")
        source.continuation?.finish()

        await waitUntil({ downloads.storedState(for: .base) == .done }, "a finished download with the file on disk must be done")
        XCTAssertEqual(completions, [.base])
    }

    func testStreamEndWithoutTheFileIsFailed() async {
        let source = StubProgressSource()
        let downloads = makeDownloads(source: source, available: false)

        downloads.start(.base)
        await waitUntil({ source.continuation != nil }, "the task never asked for a stream")
        source.continuation?.finish()

        await waitUntil({
            if case .failed = downloads.storedState(for: .base) { return true }
            return false
        }, "a stream that ends without publishing a file must fail")
    }

    func testSpeedAndEtaFromTwoSamples() {
        let (speed, eta) = ModelDownloads.rate(previous: (bytes: 1_000_000, at: 10.0), current: (bytes: 3_000_000, at: 11.0), total: 13_000_000)
        XCTAssertEqual(speed!, 2_000_000, accuracy: 1)
        XCTAssertEqual(eta!, 5, accuracy: 0.01)
        let (s2, e2) = ModelDownloads.rate(previous: nil, current: (bytes: 10, at: 1), total: 100)
        XCTAssertNil(s2); XCTAssertNil(e2)
    }

    func testSpeedWithoutEtaWhenTheTotalIsUnusable() {
        // Unknown total: a speed is still worth showing, a time left is not.
        let (speed, eta) = ModelDownloads.rate(previous: (bytes: 0, at: 0), current: (bytes: 1_000_000, at: 1), total: 0)
        XCTAssertEqual(speed!, 1_000_000, accuracy: 1)
        XCTAssertNil(eta)

        // Total already reached — the same branch, no negative time left.
        let (s2, e2) = ModelDownloads.rate(previous: (bytes: 0, at: 0), current: (bytes: 200, at: 1), total: 200)
        XCTAssertEqual(s2!, 200, accuracy: 1)
        XCTAssertNil(e2)
    }

    func testAppWindowIsFixedSizeAndTitled() {
        let w = AppWindow.make(title: "Test", size: NSSize(width: 300, height: 200), content: Text("x"))
        XCTAssertEqual(w.title, "Test")
        XCTAssertEqual(w.contentView?.frame.size, NSSize(width: 300, height: 200))
        XCTAssertFalse(w.styleMask.contains(.resizable))
        XCTAssertFalse(w.isReleasedWhenClosed)
        w.close()
    }

    // MARK: - Helpers

    /// A models directory of its own, removed after the test: the suite never
    /// reads or writes ~/Library/Application Support/SayVoice/Models.
    private func temporaryModelsDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SayVoiceTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func makeDownloads(source: StubProgressSource, available: Bool) -> ModelDownloads {
        ModelDownloads(
            modelManager: ModelManager(modelsDirectory: temporaryModelsDirectory()),
            progressSource: { source.stream(for: $0) },
            isAvailable: { _ in available }
        )
    }

    private static func fraction(_ state: DownloadState?) -> Double? {
        if case let .running(fraction, _, _) = state { return fraction }
        return nil
    }

    /// Polls on the main actor — the state machine writes from a MainActor task,
    /// so there is nothing to observe until it runs.
    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<50 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail(message, file: file, line: line)
    }
}

/// Hands `ModelDownloads` a fresh stream per start and keeps the latest
/// continuation so the test can drive the transfer by hand.
@MainActor
private final class StubProgressSource {
    private(set) var continuation: AsyncThrowingStream<ModelDownloadProgress, Error>.Continuation?

    func stream(for size: ModelManager.ModelSize) -> AsyncThrowingStream<ModelDownloadProgress, Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: ModelDownloadProgress.self, throwing: Error.self)
        self.continuation = continuation
        return stream
    }
}
