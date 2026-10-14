import SwiftUI

struct LicensesView: View {
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.dismiss) private var dismiss
    @State private var document: LegalDocument = .license

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String.appLocalized("Licenses & Acknowledgements")).font(.title2)
            Text("Copyright © 2026 Mi Remote Helper contributors. GPL-3.0-only.")
                .font(.callout)
            Text(String.appLocalized("You may redistribute and modify this software under GPL version 3. It comes without warranty. Corresponding source code is provided with each public release."))
                .font(.callout).foregroundStyle(.secondary)
            Picker(String.appLocalized("Document"), selection: $document) {
                Text("GPL-3.0-only").tag(LegalDocument.license)
                Text(String.appLocalized("Third-party notices")).tag(LegalDocument.notices)
            }
            .pickerStyle(.segmented)
            ScrollView {
                Text(document.contents)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Spacer()
                Button(String.appLocalized("Done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 650, height: 540)
    }
}

enum LegalDocument: Hashable {
    case license, notices

    var contents: String { contents(preferredLanguages: Bundle.main.preferredLocalizations) }

    func contents(preferredLanguages: [String]) -> String {
        let chinese = Bundle.preferredLocalizations(from: ["en", "zh-Hans"], forPreferences: preferredLanguages).first == "zh-Hans"
        let name = self == .license ? "LICENSE" : (chinese ? "THIRD_PARTY_NOTICES.zh-CN" : "THIRD_PARTY_NOTICES")
        let ext: String? = self == .license ? nil : "md"
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return String.appLocalized("This document could not be loaded.")
        }
        return text
    }
}
