import AppKit
import SwiftUI

/// Startup behaviour and the About card: version, source, licences.
struct SystemSection: View {
    @Bindable var settings: SettingsStore
    @State private var showingLicenses = false

    /// Public repository; shown as a link in System.
    static let repositoryURL = URL(string: "https://github.com/ashnurkoff/SayVoice")!

    var body: some View {
        VStack(spacing: DS.Space.s16) {
            Card(title: "Startup") {
                SettingsRow("Open at login") {
                    Toggle("", isOn: $settings.launchAtLogin).labelsHidden().toggleStyle(.switch)
                }
            }
            Card(title: "About") {
                SettingsRow("Version") {
                    Text(Self.versionText).font(DS.font(.valueSmall)).foregroundStyle(DS.Colors.muted.color)
                }
                SettingsRow("Source code", note: "SayVoice is open source") {
                    Button("Open on GitHub") { NSWorkspace.shared.open(Self.repositoryURL) }.buttonStyle(.dsLink)
                }
                SettingsRow("Licenses", note: "whisper.cpp, Onest, JetBrains Mono") {
                    Button("Show") { showingLicenses = true }.buttonStyle(.dsSecondary)
                }
            }
        }
        .sheet(isPresented: $showingLicenses) { LicensesSheet() }
    }

    static var versionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
