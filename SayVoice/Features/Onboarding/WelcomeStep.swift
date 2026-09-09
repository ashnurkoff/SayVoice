import SwiftUI

struct WelcomeStep: View {
    let onNext: () -> Void

    var body: some View {
        StepLayout(title: "Speak. It types.",
                   subtitle: "Hold a key, talk, release — the words land where your cursor is. Recognition runs on this Mac; nothing leaves it.",
                   centersContent: true) {
            EmptyView()
        } footer: {
            Button("Get started") { onNext() }.buttonStyle(.dsPrimary)
        }
    }
}

/// Shared step frame: title, subtitle, content, footer row. Used by all five steps.
struct StepLayout<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String
    /// Centres the title-and-content group in the pane. The steps that carry a
    /// list fill the window and stay pinned to the top; Welcome and Done hold a
    /// sentence and a mark, and those sat in the upper third of a 540 pt window
    /// with nothing under them.
    var centersContent = false
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s8) {
            if centersContent { Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                Text(title).font(DS.font(.display)).foregroundStyle(DS.Colors.text.color)
                Text(subtitle).font(DS.font(.body)).foregroundStyle(DS.Colors.muted.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
            Spacer(minLength: 0)
            HStack(spacing: DS.Space.s12) { Spacer(minLength: 0); footer() }
        }
        // 20/8 rather than the settings window's 28/16: the model step — five
        // rows with notes, a download line and a footer — already sets the
        // window's height, and wider margins would only add to it.
        .padding(DS.Space.s20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
