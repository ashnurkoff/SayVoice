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
                        note: size.purpose,
                        badge: size == .recommended ? "Recommended" : nil,
                        badgeIsAccent: size == .recommended,
                        qualitySteps: size.qualitySteps,
                        sizeText: size.sizeText,
                        isSelected: isSelected,
                        isDownloaded: isDownloaded,
                        // The warn border says "this is the one you picked and
                        // it is not on disk yet" — the same signal Settings
                        // shows when transcription finds the model missing.
                        isHighlighted: isSelected && !isDownloaded,
                        // The onboarding pane is 400 pt wide, and the note
                        // under the name needs every point of it; Settings
                        // keeps the dots.
                        showsQualityBar: false,
                        // Five rows, five notes, a download line and a footer:
                        // the pane pays for every point of row padding.
                        isCompact: true,
                        // The download control is a line of its own below the
                        // list, not one per row: five of them would not fit the
                        // window, and its status line needs the width.
                        download: nil,
                        onSelect: { model.select(size) },
                        onDownload: {},
                        onCancel: {},
                        onRetry: {}
                    )
                    // While one row is downloading, the others are not choices:
                    // they say so by stepping back rather than by going silent
                    // under a click that does nothing.
                    .opacity(model.isDownloadingTarget && size != model.runningDownload ? 0.6 : 1)
                    .animation(DS.Motion.stateChange, value: model.isDownloadingTarget)
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
