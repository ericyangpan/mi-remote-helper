import SwiftUI

struct RemoteBatteryView: View {
    let level: RemoteBatteryLevel?
    let connected: Bool

    private var currentLevel: RemoteBatteryLevel? { connected ? level : nil }
    private var description: String {
        if let level = currentLevel { return String(localized: "Battery: \(level.percentage)%") }
        return connected ? String(localized: "Battery level unavailable")
            : String(localized: "Connect the remote to read battery level.")
    }

    var body: some View {
        Label {
            if let level = currentLevel {
                Text(verbatim: "\(level.percentage)%")
            } else {
                Text(verbatim: "—")
            }
        } icon: {
            Image(systemName: currentLevel?.symbolName ?? "battery.0percent")
        }
        .font(AppTypography.caption).monospacedDigit()
        .foregroundStyle(currentLevel.map { $0.percentage <= 20 } == true ? Color.orange : Color.secondary)
        .fixedSize()
        .help(description)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(description)
        .accessibilityIdentifier("remoteBatteryLevel")
    }
}
