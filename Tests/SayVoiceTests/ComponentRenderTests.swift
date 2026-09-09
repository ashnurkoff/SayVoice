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

    func testModelRowRendersSelectedDownloadedAndDownloading() {
        // (isSelected, isDownloaded, isHighlighted, download)
        let variants: [(Bool, Bool, Bool, DownloadState?)] = [
            (true, true, false, nil),
            (false, false, false, .idle),
            (false, false, false, .running(fraction: 0.6, bytesPerSecond: 8_000_000, secondsLeft: 20)),
            (false, false, false, .failed("Timed out")),
            // The coordinator highlights the selected model when it is missing.
            (true, false, true, .idle),
        ]
        for (selected, downloaded, highlighted, download) in variants {
            for dark in [true, false] {
                let s = renderSize(modelRow(selected: selected, downloaded: downloaded, highlighted: highlighted, download: download),
                                   width: 640, dark: dark)
                XCTAssertEqual(s.width, 640, accuracy: 0.5)
                // One line without a download, two with it — compared against the
                // other variant rather than against a magic number, and bounded
                // on both sides so a runaway second line also fails.
                let oneLine = renderSize(modelRow(selected: selected, downloaded: downloaded, highlighted: highlighted, download: nil),
                                         width: 640, dark: dark)
                XCTAssertGreaterThan(oneLine.height, DS.Size.settingsRow / 2)
                XCTAssertLessThan(oneLine.height, DS.Size.settingsRow)
                if download == nil {
                    XCTAssertEqual(s.height, oneLine.height, accuracy: 0.5)
                } else {
                    XCTAssertGreaterThan(s.height, oneLine.height, "the download line adds no height")
                    XCTAssertLessThan(s.height, oneLine.height + 80, "the download line is unexpectedly tall")
                }
            }
        }
    }

    /// A long name must not push the size chip off the row: it is clamped to
    /// one line and truncated instead.
    func testModelRowKeepsALongNameOnOneLine() {
        let short = renderSize(modelRow(selected: false, downloaded: false, highlighted: false, download: nil), width: 640)
        let long = renderSize(modelRow(name: String(repeating: "Large Turbo Q5 ", count: 8),
                                       selected: false, downloaded: false, highlighted: false, download: nil), width: 640)
        XCTAssertEqual(long.height, short.height, accuracy: 0.5)
    }

    private func modelRow(name: String = "Large Turbo Q5", selected: Bool, downloaded: Bool, highlighted: Bool, download: DownloadState?) -> ModelRow {
        ModelRow(name: name, badge: "recommended", badgeIsAccent: true, qualitySteps: 4, sizeText: "574 MB",
                 isSelected: selected, isDownloaded: downloaded, isHighlighted: highlighted, download: download,
                 onSelect: {}, onDownload: {}, onCancel: {}, onRetry: {})
    }

    func testTagFieldRendersWithChips() {
        let s = renderSize(TagField(text: .constant("API, deployment, SwiftUI"), placeholder: "Add term"), width: 480)
        XCTAssertEqual(s.width, 480, accuracy: 0.5)
        XCTAssertGreaterThan(s.height, 30)
    }
}
