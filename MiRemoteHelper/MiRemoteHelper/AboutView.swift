import AppKit
import SwiftUI

struct AboutView: View {
    @ObservedObject private var localization = AppLocalization.shared
    @State private var showsLicenses = false
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—" }

    var body: some View {
        VStack(spacing: 24) {
            HStack(alignment: .center, spacing: 20) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().scaledToFit().frame(width: 80, height: 80)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                Text("Mi Remote Helper").font(AppTypography.section)
                Text(String.appLocalized("Version \(version) (\(build))"))
                    .font(AppTypography.body).foregroundStyle(.secondary)
                Text(String.appLocalized("Use your Xiaomi remote for voice input and keyboard shortcuts on your Mac."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
                Button(String.appLocalized("Licenses & Acknowledgements")) { showsLicenses = true }
                    .accessibilityIdentifier("showLicensesButton")

                VStack(alignment: .leading, spacing: 12) {
                    Text(String.appLocalized("Photo Credits")).font(AppTypography.emphasis)
                    Link(String.appLocalized("Photo: Xiaomi"), destination: URL(string: "https://www.mi.com/xiaomi-bluetooth-remote-2-pro")!)
                    Text(String.appLocalized("The photo belongs to Xiaomi or its rights holders and is not covered by the software license. Rights holders may request removal through the project’s issue tracker."))
                        .font(AppTypography.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(AppTheme.sidebar, in: RoundedRectangle(cornerRadius: 16))
            Spacer(minLength: 0)
        }
        .padding(32)
        .sheet(isPresented: $showsLicenses) { LicensesView() }
        .frame(width: 500, height: 430)
        .font(AppTypography.body)
        .background(AppTheme.canvas).foregroundStyle(AppTheme.ink).tint(AppTheme.teal)
    }
}

#Preview { AboutView() }
