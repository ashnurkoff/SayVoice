import SwiftUI

/// Model list with in-place download, then the language picker.
/// The only section allowed to scroll.
struct RecognitionSection: View {
    @Bindable var settings: SettingsStore
    let modelManager: ModelManager
    let downloads: ModelDownloads
    let router: SettingsRouter

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.s16) {
                Card(title: "Model", subtitle: "Larger models are more accurate; all run on this Mac") {
                    VStack(spacing: DS.Space.s8) {
                        ForEach(ModelManager.ModelSize.allCases, id: \.self) { model in
                            ModelRow(
                                name: model.displayName,
                                badge: model == .recommended ? "recommended" : nil,
                                badgeIsAccent: model == .recommended,
                                qualitySteps: model.qualitySteps,
                                sizeText: model.sizeText,
                                isSelected: settings.modelSize == model.settingsString,
                                isDownloaded: modelManager.isModelAvailable(model),
                                isHighlighted: router.highlightedModel == model,
                                download: downloads.state(for: model),
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
            .padding(.bottom, DS.Space.s8)
            // Room for the scroll bar, so it never sits on a card's edge.
            .padding(.trailing, DS.Space.s8)
        }
        .scrollIndicators(.automatic)
        .onDisappear { router.highlightedModel = nil }
    }
}
