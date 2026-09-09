import AppKit
import SwiftUI

/// Settings window root: icon rail on the left, section header and content
/// on the right. 780 × 600, not resizable; only Recognition may scroll.
struct SettingsView: View {
    static let windowSize = NSSize(width: 780, height: 600)
    static let railWidth: CGFloat = 64
    static let contentPadding: CGFloat = DS.Space.s28

    /// Width available to section content.
    static var contentWidth: CGFloat { windowSize.width - railWidth - 2 * contentPadding }

    let settings: SettingsStore
    let status: AppStatus
    let router: SettingsRouter
    let downloads: ModelDownloads
    let modelManager: ModelManager
    var onHotkeyChanged: ((Hotkey) -> Void)?
    var onHotkeyModeChanged: ((Bool) -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            SettingsRail(selected: router.section) { router.section = $0 }
                .frame(width: Self.railWidth)

            VStack(alignment: .leading, spacing: DS.Space.s20) {
                SectionHeader(section: router.section, status: status)
                sectionContent(router.section)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                Spacer(minLength: 0)
            }
            .padding(Self.contentPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .background(DS.Colors.ground.color)
        .font(DS.font(.body))
    }

    @ViewBuilder
    func sectionContent(_ section: SettingsSection) -> some View {
        switch section {
        case .general:
            GeneralSection(settings: settings, onHotkeyChanged: onHotkeyChanged, onHotkeyModeChanged: onHotkeyModeChanged)
        case .recognition:
            RecognitionSection(settings: settings, modelManager: modelManager, downloads: downloads, router: router)
        case .dictionary, .insertion, .system:
            PlaceholderSection(section: section)   // replaced in Task 8
        }
    }

    #if DEBUG
    /// Test hook: fitting height of a section's content at the content width,
    /// rendered on its own so the window frame cannot mask an overflow.
    /// Mirrors `body`'s column exactly — trailing `Spacer` included, since it
    /// costs one more `DS.Space.s20` gap.
    static func measuredContentHeight(for section: SettingsSection, hosting: NSHostingView<SettingsView>) -> CGFloat {
        let root = hosting.rootView
        let probe = NSHostingView(rootView: AnyView(
            VStack(alignment: .leading, spacing: DS.Space.s20) {
                SectionHeader(section: section, status: root.status)
                root.sectionContent(section)
                Spacer(minLength: 0)
            }
            .padding(contentPadding)
            .frame(width: contentWidth + 2 * contentPadding)
        ))
        probe.appearance = hosting.appearance
        return probe.fittingSize.height
    }
    #endif
}

/// Temporary stand-in while sections land one by one.
struct PlaceholderSection: View {
    let section: SettingsSection
    var body: some View {
        Card { SettingsRow("\(section.title) — coming in the next task") { EmptyView() } }
    }
}
