import AppKit
import SwiftUI

struct AboutView: View {
    @State private var showsLicenses = false
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—" }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().scaledToFit().frame(width: 96, height: 96)
                    .accessibilityHidden(true)
                Text("Mi Remote Helper").font(AppTypography.section)
                Text(String(localized: "Version \(version) (\(build))"))
                    .font(AppTypography.body).foregroundStyle(.secondary)
                Text(String(localized: "Use your Xiaomi remote for voice input and keyboard shortcuts on your Mac."))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button(String(localized: "Licenses & Acknowledgements")) { showsLicenses = true }
                    .accessibilityIdentifier("showLicensesButton")

                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "Photo Credits")).font(AppTypography.emphasis)
                    Link(String(localized: "Photo: Xiaomi"), destination: URL(string: "https://www.mi.com/xiaomi-bluetooth-remote-2-pro")!)
                    Text(String(localized: "The photo belongs to Xiaomi or its rights holders and is not covered by the software license. Rights holders may request removal through the project’s issue tracker."))
                        .font(AppTypography.body).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(AppTheme.sidebar, in: RoundedRectangle(cornerRadius: 16))
                .padding(.top, 20)
            }
            .frame(width: 380)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showsLicenses) { LicensesView() }
        .frame(width: 460, height: 490)
        .font(AppTypography.body)
        .background(AppTheme.canvas).foregroundStyle(AppTheme.ink).tint(AppTheme.teal)
    }
}

#Preview { AboutView() }
