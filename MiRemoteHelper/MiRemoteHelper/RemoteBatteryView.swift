import SwiftUI

struct RemoteBatteryView: View {
    @ObservedObject private var localization = AppLocalization.shared
    let level: RemoteBatteryLevel?
    let charging: Bool?
    let connected: Bool

    private var isCharging: Bool { connected && charging == true }
    private var batteryColor: Color {
        if isCharging { return .green }
        guard let level = currentLevel else { return .secondary }
        switch BatteryWarning.level(for: level.percentage) {
        case .critical: return .red
        case .low: return .orange
        case .normal: return .secondary
        }
    }
    private var currentLevel: RemoteBatteryLevel? { connected ? level : nil }
    private var description: String {
        if isCharging {
            if let level = currentLevel { return String.appLocalized("Charging: \(level.percentage)%") }
            return String.appLocalized("Charging")
        }
        if let level = currentLevel { return String.appLocalized("Battery: \(level.percentage)%") }
        return connected ? String.appLocalized("Battery level unavailable")
            : String.appLocalized("Connect the remote to read battery level.")
    }

    var body: some View {
        Label {
            if let level = currentLevel {
                Text(verbatim: "\(level.percentage)%")
            } else {
                Text(verbatim: "—")
            }
        } icon: {
            Image(systemName: isCharging ? "battery.100percent.bolt" : (currentLevel?.symbolName ?? "battery.0percent"))
        }
        .font(AppTypography.caption).monospacedDigit()
        .foregroundStyle(batteryColor)
        .fixedSize()
        .help(description)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(description)
        .accessibilityIdentifier("remoteBatteryLevel")
    }
}
