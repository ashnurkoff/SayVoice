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
    }

    func testSectionsAreOrderedAsSpecified() {
        XCTAssertEqual(SettingsSection.allCases.map(\.rawValue), ["general", "recognition", "dictionary", "insertion", "system"])
        for s in SettingsSection.allCases {
            XCTAssertFalse(s.title.isEmpty); XCTAssertFalse(s.subtitle.isEmpty); XCTAssertFalse(s.symbol.isEmpty)
        }
    }

    func testDownloadsReportNilForModelsOnDiskAndIdleOtherwise() {
        let downloads = ModelDownloads(modelManager: ModelManager())
        for m in ModelManager.ModelSize.allCases {
            let onDisk = ModelManager().isModelAvailable(m)
            XCTAssertEqual(downloads.state(for: m) == nil, onDisk, "\(m)")
        }
    }

    func testSpeedAndEtaFromTwoSamples() {
        let (speed, eta) = ModelDownloads.rate(previous: (bytes: 1_000_000, at: 10.0), current: (bytes: 3_000_000, at: 11.0), total: 13_000_000)
        XCTAssertEqual(speed!, 2_000_000, accuracy: 1)
        XCTAssertEqual(eta!, 5, accuracy: 0.01)
        let (s2, e2) = ModelDownloads.rate(previous: nil, current: (bytes: 10, at: 1), total: 100)
        XCTAssertNil(s2); XCTAssertNil(e2)
    }

    func testAppWindowIsFixedSizeAndTitled() {
        let w = AppWindow.make(title: "Test", size: NSSize(width: 300, height: 200), content: Text("x"))
        XCTAssertEqual(w.title, "Test")
        XCTAssertEqual(w.contentView?.frame.size, NSSize(width: 300, height: 200))
        XCTAssertFalse(w.styleMask.contains(.resizable))
        XCTAssertFalse(w.isReleasedWhenClosed)
        w.close()
    }
}
