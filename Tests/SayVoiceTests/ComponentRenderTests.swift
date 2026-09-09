import SwiftUI
import XCTest
@testable import SayVoice

/// Smoke tests: each component renders to a bitmap with a sane size in
/// both appearances. They catch layout that collapses to zero and code
/// paths that crash off-screen; they do not judge looks.
@MainActor
final class ComponentRenderTests: XCTestCase {

    func renderSize<V: View>(_ view: V, width: CGFloat? = nil, dark: Bool = true) -> CGSize {
        let host = NSHostingView(rootView: AnyView(view.fixedSize(horizontal: width == nil, vertical: true).frame(width: width)))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let size = host.fittingSize
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)
        XCTAssertNotNil(rep)
        if let rep { host.cacheDisplay(in: host.bounds, to: rep) }
        return size
    }

    func testChipRendersAllStyles() {
        for style in [Chip.Style.neutral, .accent, .ok, .warn] {
            for dark in [true, false] {
                let s = renderSize(Chip("recommended", style: style), dark: dark)
                XCTAssertGreaterThan(s.width, 40); XCTAssertGreaterThan(s.height, 16); XCTAssertLessThan(s.height, 30)
            }
        }
    }

    func testKeyCapRenders() {
        let s = renderSize(KeyCap("⌃⌥⌘D"))
        XCTAssertGreaterThan(s.width, 40); XCTAssertGreaterThan(s.height, 20)
    }

    func testButtonStylesRender() {
        XCTAssertGreaterThan(renderSize(Button("Download") {}.buttonStyle(.dsPrimary)).height, 24)
        XCTAssertGreaterThan(renderSize(Button("Stop") {}.buttonStyle(.dsSecondary)).height, 24)
        XCTAssertGreaterThan(renderSize(Button("Copy") {}.buttonStyle(.dsLink)).height, 14)
        XCTAssertGreaterThan(renderSize(Button("Clear…") {}.buttonStyle(.dsDestructive)).height, 14)
    }

    func testOrbRendersEveryState() {
        for state in [Orb.State.idle, .recording, .transcribing, .done, .error] {
            let s = renderSize(Orb(state: state))
            XCTAssertEqual(s.width, DS.Size.orb + 10, accuracy: 0.5, "orb frame includes the 5pt halo ring")
            XCTAssertEqual(s.height, DS.Size.orb + 10, accuracy: 0.5)
        }
    }

    /// The done mark draws itself in: 0.6 → 1 and transparent → opaque, driven
    /// by the orb's `drawnIn` flag. No other state has an entrance, and Reduce
    /// Motion removes it — the mark is then simply there.
    func testOnlyTheDoneMarkDrawsItselfIn() {
        for state in [Orb.State.idle, .recording, .transcribing, .error] {
            XCTAssertFalse(Orb.isDrawingIn(state: state, drawnIn: false, reduceMotion: false), "\(state)")
            XCTAssertEqual(Orb.drawInScale(state: state, drawnIn: false, reduceMotion: false), 1, "\(state)")
            XCTAssertEqual(Orb.drawInOpacity(state: state, drawnIn: false, reduceMotion: false), 1, "\(state)")
        }

        XCTAssertTrue(Orb.isDrawingIn(state: .done, drawnIn: false, reduceMotion: false))
        XCTAssertEqual(Orb.drawInScale(state: .done, drawnIn: false, reduceMotion: false), 0.6)
        XCTAssertEqual(Orb.drawInOpacity(state: .done, drawnIn: false, reduceMotion: false), 0)

        // Once it has drawn in, it is at rest like everything else.
        XCTAssertEqual(Orb.drawInScale(state: .done, drawnIn: true, reduceMotion: false), 1)
        XCTAssertEqual(Orb.drawInOpacity(state: .done, drawnIn: true, reduceMotion: false), 1)

        // Reduce Motion: no entrance at all, whatever the flag says.
        XCTAssertFalse(Orb.isDrawingIn(state: .done, drawnIn: false, reduceMotion: true))
        XCTAssertEqual(Orb.drawInScale(state: .done, drawnIn: false, reduceMotion: true), 1)
        XCTAssertEqual(Orb.drawInOpacity(state: .done, drawnIn: false, reduceMotion: true), 1)
    }

    func testGlassPanelRendersBothShapes() {
        for shape in [GlassPanel<Text>.Shape.capsule, .card] {
            let s = renderSize(GlassPanel(shape: shape) { Text("Listening") })
            XCTAssertEqual(s.width, DS.Size.overlayWidth, accuracy: 0.5)
            XCTAssertGreaterThan(s.height, 30)
        }
    }

    func testCardAndRowRender() {
        let s = renderSize(
            Card(title: "Recording hotkey", subtitle: "Key, combination or mouse button") {
                SettingsRow("Show overlay", note: "Glass capsule at the bottom of the screen") { Toggle("", isOn: .constant(true)).labelsHidden() }
                SettingsRow("Sound feedback") { Toggle("", isOn: .constant(false)).labelsHidden() }
            },
            width: 600
        )
        XCTAssertEqual(s.width, 600, accuracy: 0.5)
        XCTAssertGreaterThan(s.height, 2 * DS.Size.settingsRow)
    }

    /// Item 9 of the owner's first round: rows with a multi-line note were
    /// cramped and the note ran all the way up to the control. The row now pays
    /// 12 pt above and below, 4 pt between label and note, and the note wraps
    /// inside 60% of the row.
    func testSettingsRowBreathesAndCapsTheNoteWidth() {
        let long = "Writes straight into the focused field through the accessibility API; the clipboard is untouched. "
                 + "Works in native apps (TextEdit, Notes, Xcode, Safari). Chrome, Electron and Terminal do not expose it."
        let width: CGFloat = 600
        let rowWidth = width - 2 * DS.Space.s16

        for dark in [true, false] {
            let plain = renderSize(SettingsRow("Method") { Toggle("", isOn: .constant(true)).labelsHidden() },
                                   width: width, dark: dark)
            let noted = renderSize(SettingsRow("Method", note: long) { Toggle("", isOn: .constant(true)).labelsHidden() },
                                   width: width, dark: dark)
            XCTAssertEqual(plain.height, DS.Size.settingsRow, accuracy: 0.5, "a bare row keeps the 44 pt height")
            XCTAssertGreaterThan(noted.height, plain.height)

            // The note is laid out at the cap, not at whatever the control left over.
            let cap = rowWidth * SettingsRowLayout.noteWidthFraction
            let capped = renderSize(Text(long).font(DS.font(.caption)).fixedSize(horizontal: false, vertical: true),
                                    width: cap, dark: dark)
            let loose = renderSize(Text(long).font(DS.font(.caption)).fixedSize(horizontal: false, vertical: true),
                                   width: rowWidth - 60, dark: dark)
            XCTAssertGreaterThan(capped.height, loose.height, "precondition: the cap costs the note extra lines")
            XCTAssertGreaterThanOrEqual(noted.height, capped.height + 2 * DS.Space.s12,
                                        "the note wrapped wider than the cap, or the row lost its padding")
        }
    }

    func testDownloadProgressRendersEveryState() {
        let states: [DownloadState] = [.idle, .running(fraction: 0.34, bytesPerSecond: 12_400_000, secondsLeft: 38), .failed("The network connection was lost."), .done]
        for state in states {
            for dark in [true, false] {
                let s = renderSize(DownloadProgress(state: state, onStart: {}, onCancel: {}, onRetry: {}), width: 480, dark: dark)
                XCTAssertEqual(s.width, 480, accuracy: 0.5)
                XCTAssertGreaterThan(s.height, 20)
            }
        }
    }

    /// The row is two columns and, until a transfer starts, two lines: the
    /// Download button and the "Downloaded" mark share the right column with
    /// the size (owner's second round, item 11 and its addendum). Only a
    /// running or failed transfer adds the full-width line.
    func testModelRowIsTwoLinesUntilATransferStarts() {
        let running = DownloadState.running(fraction: 0.6, bytesPerSecond: 8_000_000, secondsLeft: 20)
        for dark in [true, false] {
            let note = ModelManager.ModelSize.turboQ5.purpose
            let downloaded = renderSize(modelRow(note: note, selected: true, downloaded: true, highlighted: false, download: nil),
                                        width: 640, dark: dark)
            let offered = renderSize(modelRow(note: note, selected: false, downloaded: false, highlighted: false, download: .idle),
                                     width: 640, dark: dark)
            let transferring = renderSize(modelRow(note: note, selected: false, downloaded: false, highlighted: false, download: running),
                                          width: 640, dark: dark)
            let failed = renderSize(modelRow(note: note, selected: false, downloaded: false, highlighted: false, download: .failed("Timed out")),
                                    width: 640, dark: dark)

            for s in [downloaded, offered, transferring, failed] {
                XCTAssertEqual(s.width, 640, accuracy: 0.5)
            }
            XCTAssertLessThanOrEqual(downloaded.height, Self.twoLineRowCap,
                                     "a downloaded row is \(downloaded.height) pt — taller than two lines")
            XCTAssertLessThanOrEqual(offered.height, Self.twoLineRowCap,
                                     "the Download button took a line of its own (\(offered.height) pt)")
            XCTAssertGreaterThan(transferring.height, offered.height + 20, "the transfer line adds no height")
            XCTAssertGreaterThan(failed.height, offered.height, "the failure line adds no height")
            XCTAssertLessThan(transferring.height, offered.height + 80, "the transfer line is unexpectedly tall")
        }
    }

    /// Two lines of text on the left, and on the right the size, the quality
    /// dots and one status control. Measured, not chosen: the tallest such row
    /// — the one offering a `.dsPrimary` Download button — is 73 pt.
    private static let twoLineRowCap: CGFloat = 78

    /// The highlighted state (the selected model missing from disk) renders at
    /// the same size as the plain one: it differs by a border colour only.
    func testModelRowHighlightCostsNoLayout() {
        for dark in [true, false] {
            let plain = renderSize(modelRow(selected: true, downloaded: false, highlighted: false, download: .idle), width: 640, dark: dark)
            let highlighted = renderSize(modelRow(selected: true, downloaded: false, highlighted: true, download: .idle), width: 640, dark: dark)
            XCTAssertEqual(highlighted.height, plain.height, accuracy: 0.5)
        }
    }

    /// Without the quality dots — the onboarding pane — the row is shorter.
    func testModelRowWithoutTheQualityBarIsShorter() {
        let note = ModelManager.ModelSize.turboQ5.purpose
        let withBar = renderSize(modelRow(note: note, selected: false, downloaded: true, highlighted: false, download: nil), width: 640)
        let without = renderSize(modelRow(note: note, selected: false, downloaded: true, highlighted: false, download: nil, qualityBar: false), width: 640)
        XCTAssertLessThanOrEqual(without.height, withBar.height)
    }

    /// The purpose note sits under the name in the left column, and wraps
    /// rather than truncates when that column is narrow. Both baselines are
    /// measured without a download: with one, the right column is the taller
    /// of the two and the note's own height stops showing up in the total.
    func testModelRowShowsAWrappingPurposeNote() {
        for dark in [true, false] {
            let plain = renderSize(modelRow(selected: false, downloaded: false, highlighted: false, download: nil),
                                   width: 640, dark: dark)
            let noted = renderSize(modelRow(note: ModelManager.ModelSize.turboQ5.purpose,
                                            selected: false, downloaded: false, highlighted: false, download: nil),
                                   width: 640, dark: dark)
            XCTAssertGreaterThan(noted.height, plain.height, "the note adds no height")
            XCTAssertLessThan(noted.height, plain.height + 24, "the note took more than one line at 640 pt")

            // The onboarding pane is narrower than the note's ideal width, so
            // there it must wrap onto a second line instead of being cut off.
            let narrow = renderSize(modelRow(note: ModelManager.ModelSize.turboQ5.purpose,
                                             selected: false, downloaded: false, highlighted: false, download: nil),
                                    width: 320, dark: dark)
            let narrowPlain = renderSize(modelRow(selected: false, downloaded: false, highlighted: false, download: nil),
                                         width: 320, dark: dark)
            XCTAssertGreaterThan(narrow.height, narrowPlain.height + 24, "the note truncated instead of wrapping")
        }
    }

    /// A long name must not push the size off the row: it is clamped to one
    /// line and truncated instead.
    func testModelRowKeepsALongNameOnOneLine() {
        let short = renderSize(modelRow(selected: false, downloaded: false, highlighted: false, download: nil), width: 640)
        let long = renderSize(modelRow(name: String(repeating: "Large Turbo Q5 ", count: 8),
                                       selected: false, downloaded: false, highlighted: false, download: nil), width: 640)
        XCTAssertEqual(long.height, short.height, accuracy: 0.5)
    }

    private func modelRow(name: String = "Large Turbo Q5", note: String? = nil,
                          selected: Bool, downloaded: Bool, highlighted: Bool, download: DownloadState?,
                          qualityBar: Bool = true) -> ModelRow {
        ModelRow(name: name, note: note, badge: "Recommended", badgeIsAccent: true, qualitySteps: 4, sizeText: "574 MB",
                 isSelected: selected, isDownloaded: downloaded, isHighlighted: highlighted,
                 showsQualityBar: qualityBar, download: download,
                 onSelect: {}, onDownload: {}, onCancel: {}, onRetry: {})
    }

    func testTagFieldRendersWithChips() {
        for dark in [true, false] {
            let empty = renderSize(TagField(text: .constant(""), placeholder: "Add term"), width: 480, dark: dark)
            let chips = renderSize(TagField(text: .constant("API, deployment, SwiftUI"), placeholder: "Add term"), width: 480, dark: dark)
            XCTAssertGreaterThan(empty.height, 30, "the field collapsed")
            XCTAssertEqual(chips.width, 480, accuracy: 0.5)
            // Chips make the field grow downwards, never sideways: the flow
            // layout must wrap them inside the container it was given.
            XCTAssertLessThanOrEqual(chips.width, empty.width)
            XCTAssertGreaterThanOrEqual(chips.height, empty.height)
        }
    }
}
