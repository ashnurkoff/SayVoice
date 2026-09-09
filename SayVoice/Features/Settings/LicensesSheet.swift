import SwiftUI

/// Third-party licences, read from the bundle so the text shown is the text shipped.
struct LicensesSheet: View {
    @Environment(\.dismiss) private var dismiss

    struct Item: Identifiable {
        let name: String
        let license: String
        let text: String
        var id: String { name }
    }

    static let items: [Item] = [
        Item(name: "whisper.cpp", license: "MIT", text: load("whisper.cpp-LICENSE", subdirectory: nil)),
        Item(name: "Onest", license: "SIL Open Font License 1.1", text: load("Onest-OFL", subdirectory: "Fonts")),
        Item(name: "JetBrains Mono", license: "SIL Open Font License 1.1", text: load("JetBrainsMono-OFL", subdirectory: "Fonts")),
    ]

    private static func load(_ name: String, subdirectory: String?) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: subdirectory),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            HStack {
                Text("Licenses").font(DS.font(.title)).foregroundStyle(DS.Colors.text.color)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.dsSecondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s20) {
                    ForEach(Self.items) { item in
                        VStack(alignment: .leading, spacing: DS.Space.s8) {
                            HStack(spacing: DS.Space.s8) {
                                Text(item.name).font(DS.font(.bodyMedium)).foregroundStyle(DS.Colors.text.color)
                                Chip(item.license)
                            }
                            Text(item.text)
                                .font(DS.font(.caption))
                                .foregroundStyle(DS.Colors.muted.color)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(DS.Space.s20)
        .frame(width: 560, height: 480)
        .background(DS.Colors.ground.color)
    }
}
