import SwiftUI

struct PermissionsStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        StepLayout(title: "Two permissions",
                   subtitle: "Microphone to hear you; Accessibility for the global hotkey and to insert text.") {
            Card {
                PermissionRow(name: "Microphone", granted: model.microphoneGranted,
                              actionTitle: "Allow") { model.requestMicrophone() }
                PermissionRow(name: "Accessibility", granted: model.accessibilityGranted,
                              actionTitle: "Open System Settings") { model.openAccessibility() }
            }
        } footer: {
            Button("Continue") { model.next() }.buttonStyle(.dsPrimary).disabled(!model.canContinue)
        }
        .onAppear { model.refreshPermissions(); model.startPolling() }
        .onDisappear { model.stopPolling() }
    }
}

private struct PermissionRow: View {
    let name: String
    let granted: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        SettingsRow(name, note: granted ? "Granted" : "Not yet") {
            if granted {
                Chip("granted", style: .ok)
            } else {
                Button(actionTitle) { action() }.buttonStyle(.dsSecondary)
            }
        }
    }
}
