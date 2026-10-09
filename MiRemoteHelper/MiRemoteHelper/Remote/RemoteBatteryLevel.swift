import Foundation

struct RemoteBatteryLevel: Equatable {
    let percentage: Int

    /// Bluetooth Battery Level (2A19) is a single unsigned percentage byte.
    init?(data: Data) {
        guard data.count == 1, let value = data.first, value <= 100 else { return nil }
        percentage = Int(value)
    }

    var symbolName: String {
        switch percentage {
        case 0...10: return "battery.0percent"
        case 11...37: return "battery.25percent"
        case 38...62: return "battery.50percent"
        case 63...87: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
