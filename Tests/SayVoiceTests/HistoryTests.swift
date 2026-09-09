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

    @MainActor
    func testCompactStatusPillFitsThePopoverHeaderOnOneLine() {
        let status = AppStatus(); status.modelName = "Large Turbo Q5"
        XCTAssertEqual(status.pillText, "Ready \u{00B7} Large Turbo Q5")
        XCTAssertEqual(status.compactText, "Ready")
        // Before the coordinator names a model, both forms are the bare word.
        XCTAssertEqual(AppStatus().pillText, "Ready")
        XCTAssertEqual(AppStatus().compactText, "Ready")

        for dark in [true, false] {
            let full = idealSize(StatusPill(status: status), dark: dark)
            let compact = idealSize(StatusPill(status: status, compact: true), dark: dark)
            XCTAssertLessThan(compact.width, full.width, "compact drops the model name")
            XCTAssertEqual(compact.height, full.height, accuracy: 0.5, "both stay one line")

            // What the header leaves the pill at 320 pt: the popover's own
            // horizontal padding, the 22 pt logo, the two 8 pt gaps and the
            // "SayVoice" label.
            let label = idealSize(Text("SayVoice").font(DS.font(.bodyMedium)), dark: dark)
            let budget = HistoryPopover.width - 2 * DS.Space.s12 - 22 - 2 * DS.Space.s8 - label.width
            XCTAssertLessThanOrEqual(compact.width, budget,
                                     "the compact pill must fit the header without wrapping")
        }
    }

    /// Ideal (unwrapped) size of a view, so a label that would wrap under a
    /// narrower parent still reports the width it really wants.
    @MainActor
    private func idealSize<V: View>(_ view: V, dark: Bool) -> CGSize {
        let host = NSHostingView(rootView: AnyView(view.fixedSize()))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }
}
