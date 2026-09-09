import SwiftUI

struct ModelStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        StepLayout(title: "Pick a model",
                   subtitle: "Large Turbo Q5 is the sweet spot. All five models are in Settings → Recognition.") {
            VStack(spacing: DS.Space.s8) {
                ForEach(OnboardingModel.offeredModels, id: \.self) { size in
                    ModelRow(
                        name: size.displayName,
                        badge: size == .recommended ? "recommended" : nil,
                        badgeIsAccent: size == .recommended,
                        qualitySteps: size.qualitySteps,
                        sizeText: size.sizeText,
                        isSelected: model.settings.modelSize == size.settingsString,
                        isDownloaded: model.modelManager.isModelAvailable(size),
                        // The download control is in the footer, not in the row:
                        // three of them do not fit a 360 pt window.
                        download: nil,
                        onSelect: { model.settings.modelSize = size.settingsString },
                        onDownload: {},
                        onCancel: {},
                        onRetry: {}
                    )
                }
            }
        } footer: {
            let target = model.downloadTarget
            if let state = model.downloads.state(for: target) {
                // Skipping does not stop a running transfer: the downloads
                // coordinator belongs to the app, not to this window.
                Button("Download later") { model.skip() }.buttonStyle(.dsLink)
                DownloadProgress(state: state,
                                 onStart: { model.downloads.start(target) },
                                 onCancel: { model.downloads.cancel(target) },
                                 onRetry: { model.downloads.start(target) })
                    .frame(width: 200)
            } else {
                Button("Continue") { model.next() }.buttonStyle(.dsPrimary)
            }
        }
    }
}
