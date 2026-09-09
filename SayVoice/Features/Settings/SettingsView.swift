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

            column
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .background(DS.Colors.ground.color)
        .font(DS.font(.body))
        // System controls draw their on-state in the system accent otherwise —
        // a blue toggle in an indigo app. One tint at the root covers every
        // toggle, segmented picker and menu picker the window hosts (spec 3.1:
        // the active control is the accent).
        .tint(DS.Colors.accent.color)
        // The header pill names the selected model, so it follows the choice.
        .onChange(of: settings.modelSize) { _, new in
            status.modelName = (ModelManager.ModelSize(settingsString: new) ?? .recommended).displayName
        }
    }

    /// The content column. A scrolling section keeps the header's margins but
    /// hands the rest of the height to its own scroll area, which then reaches
    /// the window's bottom edge; every other section sits inside the full 28 pt
    /// margin with a spacer under it.
    @ViewBuilder
    private var column: some View {
        if router.section.scrollsToBottomEdge {
            VStack(alignment: .leading, spacing: DS.Space.s20) {
                SectionHeader(section: router.section, status: status)
                    .padding(.horizontal, Self.contentPadding)
                sectionContent(router.section)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    // No trailing padding: the section draws its own closing
                    // hairline flush with the window.
                    .padding(.leading, Self.contentPadding)
            }
            .padding(.top, Self.contentPadding)
        } else {
            VStack(alignment: .leading, spacing: DS.Space.s20) {
                SectionHeader(section: router.section, status: status)
                sectionContent(router.section)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                Spacer(minLength: 0)
            }
            .padding(Self.contentPadding)
        }
    }

    @ViewBuilder
    func sectionContent(_ section: SettingsSection) -> some View {
        switch section {
        case .general:
            GeneralSection(settings: settings, onHotkeyChanged: onHotkeyChanged, onHotkeyModeChanged: onHotkeyModeChanged)
        case .recognition:
            RecognitionSection(settings: settings, modelManager: modelManager, downloads: downloads, router: router)
        case .dictionary:
            DictionarySection(settings: settings)
        case .insertion:
            InsertionSection(settings: settings)
        case .system:
            SystemSection(settings: settings)
        }
    }

    #if DEBUG
    /// Test hook: fitting height of a section's content at the content width,
    /// rendered on its own so the window frame cannot mask an overflow.
    /// Mirrors the column of a section that does not scroll — trailing `Spacer`
    /// included, since it costs one more `DS.Space.s20` gap. Measuring the
    /// scrolling section this way reports the height its content *wants*, which
    /// is exactly what its own test asks about.
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
