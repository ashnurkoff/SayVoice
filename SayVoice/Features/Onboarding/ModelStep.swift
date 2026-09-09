import SwiftUI

struct ModelStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        let target = model.downloadTarget
        let download = model.downloads.state(for: target)
        StepLayout(title: "Pick a model",
                   subtitle: "Large Turbo Q5 is the sweet spot. You can change this later in Settings.") {
            VStack(spacing: DS.Space.s4) {
                ForEach(OnboardingModel.offeredModels, id: \.self) { size in
                    let isSelected = model.settings.modelSize == size.settingsString
                    let isDownloaded = model.modelManager.isModelAvailable(size)
                    ModelRow(
                        name: size.displayName,
                        badge: size == .recommended ? "recommended" : nil,
                        badgeIsAccent: size == .recommended,
                        qualitySteps: size.qualitySteps,
                        sizeText: size.sizeText,
                        isSelected: isSelected,
                        isDownloaded: isDownloaded,
                        // The warn border says "this is the one you picked and
                        // it is not on disk yet" — the same signal Settings
                        // shows when transcription finds the model missing.
                        isHighlighted: isSelected && !isDownloaded,
                        // The onboarding pane leaves no room for the bar next to
                        // the name and the chips; Settings keeps it.
                        showsQualityBar: false,
                        // The download control is a line of its own below the
                        // list, not one per row: five of them would not fit the
                        // window, and its status line needs the width.
                        download: nil,
                        onSelect: { model.settings.modelSize = size.settingsString },
                        onDownload: {},
                        onCancel: {},
                        onRetry: {}
                    )
                }
                if let download {
                    DownloadProgress(state: download,
                                     prominent: true,
                                     onStart: { model.downloads.start(target) },
                                     onCancel: { model.downloads.cancel(target) },
                                     onRetry: { model.downloads.start(target) })
                }
            }
        } footer: {
            if model.isDownloadingTarget {
                // A transfer under way pins the step: Cancel, on the line above,
                // is the way out. Leaving would start the app without the model
                // it is fetching, and "Download later" would be a lie.
                Button("Continue") { model.next() }.buttonStyle(.dsPrimary).disabled(true)
            } else if download != nil {
                Button("Download later") { model.skip() }.buttonStyle(.dsLink)
            } else {
                Button("Continue") { model.next() }.buttonStyle(.dsPrimary)
            }
        }
    }
}
