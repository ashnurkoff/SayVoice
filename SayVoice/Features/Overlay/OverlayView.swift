import SwiftUI

/// Root of the overlay. One glass panel of fixed width; the state decides
/// whether it is a capsule (recording, transcribing) or a card (result,
/// error) and what goes inside. Width never changes between states.
struct OverlayView: View {
    let model: OverlayModel

    var body: some View {
        ZStack {
            // Transparent backing the size of the panel. Without it the hosting
            // view collapses in .hidden, the window shrinks around it, and the
            // next show is centred on the collapsed size. Color.clear draws
            // nothing and does not wake the render loop.
            // Hit-testing off: the backing spans the whole 640x280 panel, and
            // with mouse events enabled it would swallow clicks far outside
            // the drawn glass. Only the panel itself should catch the pointer.
            Color.clear
                .allowsHitTesting(false)

            if model.displayState != .hidden {
                GlassPanel(shape: isCard ? .card : .capsule) {
                    content
                }
                .onHover { model.isHovered = $0 }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(DS.Motion.stateChange, value: model.displayState)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isCard: Bool {
        model.displayState == .result || model.displayState == .error
    }

    @ViewBuilder private var content: some View {
        switch model.displayState {
        case .hidden:       EmptyView()
        case .recording:    RecordingContent(model: model)
        case .transcribing: TranscribingContent()
        case .result:       ResultContent(model: model)
        case .error:        ErrorContent(model: model)
        }
    }
}
