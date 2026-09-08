import SwiftUI

struct ModelDownloadView: View {
    let modelManager: ModelManager
    let modelSize: ModelManager.ModelSize
    let onComplete: () -> Void

    @State private var progress: Double = 0
    @State private var isDownloading = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Модель не найдена")
                .font(.headline)

            Text("Для транскрипции нужна модель Whisper \(modelSize.displayName) (\(modelSize.fileSize))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if isDownloading {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)

                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)

                Button("Повторить") { startDownload() }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Скачать модель") { startDownload() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 320)
    }

    private func startDownload() {
        isDownloading = true
        error = nil
        progress = 0

        Task {
            do {
                for try await p in modelManager.downloadModel(modelSize) {
                    progress = p
                }
                onComplete()
            } catch {
                self.error = error.localizedDescription
                isDownloading = false
            }
        }
    }
}
