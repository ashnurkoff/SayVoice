import SwiftUI
import XCTest
@testable import SayVoice

final class HistoryTests: XCTestCase {

    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)   // a fixed instant

    func testCoarseRelativeTime() {
        let cal = Calendar(identifier: .gregorian)
        XCTAssertEqual(RelativeTime.coarse(now.addingTimeInterval(-20), now: now, calendar: cal), "just now")
        XCTAssertEqual(RelativeTime.coarse(now.addingTimeInterval(-5 * 60), now: now, calendar: cal), "5 min")
        XCTAssertEqual(RelativeTime.coarse(now.addingTimeInterval(-3 * 3600), now: now, calendar: cal), "3 h")
        XCTAssertEqual(RelativeTime.coarse(cal.date(byAdding: .day, value: -1, to: now)!, now: now, calendar: cal), "yesterday")
        XCTAssertEqual(RelativeTime.coarse(cal.date(byAdding: .day, value: -4, to: now)!, now: now, calendar: cal), "4 d")
        let old = cal.date(byAdding: .day, value: -40, to: now)!
        XCTAssertEqual(RelativeTime.coarse(old, now: now, calendar: cal), old.formatted(.dateTime.day().month(.abbreviated)))
    }

    func testFilterIsCaseInsensitiveSubstringAndKeepsOrder() {
        let e = [TranscriptionEntry(text: "Deploy the API tonight", durationSeconds: 2),
                 TranscriptionEntry(text: "buy milk", durationSeconds: 1),
                 TranscriptionEntry(text: "api keys rotated", durationSeconds: 3)]
        XCTAssertEqual(HistoryFilter.apply(e, query: "").map(\.text), e.map(\.text))
        XCTAssertEqual(HistoryFilter.apply(e, query: "  api ").map(\.text), ["Deploy the API tonight", "api keys rotated"])
        XCTAssertEqual(HistoryFilter.apply(e, query: "zzz"), [])
    }

    @MainActor
    func testEmptyStateRenders() {
        for dark in [true, false] {
            let host = NSHostingView(rootView: EmptyState(symbol: "waveform", title: "No dictations yet", hint: "Hold Right ⌥ and speak."))
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            host.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
            host.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(host.fittingSize.height, 60)
        }
    }

    @MainActor
    func testHistoryPopoverRendersEmptyAndFilled() {
        let status = AppStatus(); status.modelName = "Large Turbo Q5"
        let entries = (0..<3).map { TranscriptionEntry(text: "Entry \($0) with enough words to wrap onto a second line in the popover", durationSeconds: 4.2, language: "en") }
        for list in [[], entries] {
            for dark in [true, false] {
                let host = NSHostingView(rootView: HistoryPopover(entries: list, status: status, hotkeyName: "Right ⌥", onClear: {}, onSettings: {}))
                host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                host.layoutSubtreeIfNeeded()
                let s = host.fittingSize
                XCTAssertEqual(s.width, HistoryPopover.width, accuracy: 0.5)
                XCTAssertGreaterThan(s.height, list.isEmpty ? 120 : 200)
                XCTAssertLessThanOrEqual(s.height, 520)
            }
        }
    }
}
