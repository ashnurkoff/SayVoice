import AppKit
import Combine
import SwiftUI

/// First-run window: art panel on the left, one step at a time on the right.
struct OnboardingView: View {
    /// 640 × 540. The model step lists all five models with a purpose note
    /// under each name and keeps the download control below the list; measured
    /// at its tallest — a running transfer with speed and time left — that step
    /// wants 526 pt, so 360 (and the 420 first proposed) could not hold it.
    static let windowSize = NSSize(width: 640, height: 540)
    /// Width the art panel leaves to a step.
    static var stepWidth: CGFloat { windowSize.width - ArtPanel.width }

    let model: OnboardingModel
    var onHotkeyChanged: ((Hotkey) -> Void)?
    var onHotkeyModeChanged: ((Bool) -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            ArtPanel(step: model.step)
            stepContent(model.step)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(DS.Motion.stateChange, value: model.step)
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .background(DS.Colors.ground.color)
        .font(DS.font(.body))
        // As in Settings: the Hold/Toggle picker is a system control and would
        // otherwise pick the system accent.
        .tint(DS.Colors.accent.color)
        // The permission poll is stopped by the coordinator, which observes
        // `willClose` on the onboarding window itself. An unfiltered observer
        // here would fire for any window the app ever closes.
    }

    @ViewBuilder
    func stepContent(_ step: OnboardingStep) -> some View {
        switch step {
        case .welcome:     WelcomeStep(onNext: { model.next() })
        case .permissions: PermissionsStep(model: model)
        case .model:       ModelStep(model: model)
        case .hotkey:      HotkeyStep(model: model, onHotkeyChanged: onHotkeyChanged, onHotkeyModeChanged: onHotkeyModeChanged)
        case .done:        DoneStep(model: model)
        }
    }

    #if DEBUG
    /// Test hook: fitting size of one step's pane on its own, at the width the
    /// art panel leaves it. The window's fixed frame reports 640 × 360 whatever
    /// the content does, so an overflow is only visible when the pane is
    /// measured outside it — same reason as `SettingsView.measuredContentHeight`.
    static func measuredStepSize(for step: OnboardingStep, in view: OnboardingView, appearance: NSAppearance?) -> NSSize {
        let probe = NSHostingView(rootView: AnyView(view.stepContent(step).frame(width: stepWidth)))
        probe.appearance = appearance
        return probe.fittingSize
    }
    #endif
}
