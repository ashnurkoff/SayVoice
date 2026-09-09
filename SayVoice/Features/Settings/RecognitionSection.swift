import SwiftUI

/// The language picker, then the model list with in-place download.
/// The only section allowed to scroll, and the only one whose content runs to
/// the window's bottom edge.
struct RecognitionSection: View {
    /// Card order (spec §5.1, amended after the owner's first live test):
    /// Language first. It is a single row and the setting changed most often,
    /// and below five model rows it needed a scroll to reach.
    /// Named `CardKind` rather than `Card`: the design system already owns
    /// that name, and this enum only orders the two cards.
    enum CardKind: Hashable { case language, model }
    static let cardOrder: [CardKind] = [.language, .model]

    @Bindable var settings: SettingsStore
    let modelManager: ModelManager
    let downloads: ModelDownloads
    let router: SettingsRouter

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: DS.Space.s16) {
                    ForEach(Self.cardOrder, id: \.self) { card in
                        switch card {
                        case .language: languageCard
                        case .model:    modelCard
                        }
                    }
                }
                .padding(.bottom, DS.Space.s16)
                // Room for the scroll bar, so it never sits on a card's edge.
                .padding(.trailing, DS.Space.s8)
            }
            // Shown rather than overlaid on demand: this is the one section that
            // scrolls, and nothing else on screen says so.
            .scrollIndicators(.visible)

            // The scroll area reaches the window's bottom edge — no dead strip
            // under it — and this hairline closes it, so a card cut off by the
            // edge reads as "there is more" rather than as a rendering fault.
            Rectangle().fill(DS.Colors.line.color).frame(height: 1)
        }
        .onDisappear { router.highlightedModel = nil }
    }

    private var modelCard: some View {
        Card(title: "Model", subtitle: "Larger models are more accurate; all run on this Mac") {
            VStack(spacing: DS.Space.s8) {
                ForEach(ModelManager.ModelSize.allCases, id: \.self) { model in
                    ModelRow(
                        name: model.displayName,
                        note: model.purpose,
                        badge: model == .recommended ? "Recommended" : nil,
                        badgeIsAccent: model == .recommended,
                        qualitySteps: model.qualitySteps,
                        sizeText: model.sizeText,
                        isSelected: settings.modelSize == model.settingsString,
                        isDownloaded: modelManager.isModelAvailable(model),
                        isHighlighted: router.highlightedModel == model,
                        download: downloads.state(for: model),
                        // At most one primary per screen: the row the
                        // user has actually picked.
                        downloadIsProminent: settings.modelSize == model.settingsString,
                        onSelect: {
                            settings.modelSize = model.settingsString
                            router.highlightedModel = nil
                        },
                        onDownload: {
                            downloads.start(model)
                            router.highlightedModel = nil
                        },
                        onCancel: { downloads.cancel(model) },
                        onRetry: {
                            downloads.start(model)
                            router.highlightedModel = nil
                        }
                    )
                }
            }
            // 16 pt, like SettingsRow: the row borders start at the
            // same x as the hairlines in the Language card.
            .padding(.horizontal, DS.Space.s16)
            .padding(.top, DS.Space.s4)
        }
    }

    private var languageCard: some View {
        Card(title: "Language") {
            SettingsRow("Recognition language", note: "Set it explicitly when auto-detection gets it wrong — Russian speech with English terms, for example") {
                Picker("", selection: $settings.language) {
                    Text("Auto").tag("auto")
                    Divider()
                    Text("English").tag("en")
                    Divider()
                    Text("Deutsch").tag("de")
                    Text("Español").tag("es")
                    Text("Français").tag("fr")
                    Text("Italiano").tag("it")
                    Text("Nederlands").tag("nl")
                    Text("Polski").tag("pl")
                    Text("Português").tag("pt")
                    Text("Türkçe").tag("tr")
                    Text("Русский").tag("ru")
                    Text("Українська").tag("uk")
                }
                .labelsHidden()
                .frame(width: 160)
            }
        }
    }
}
