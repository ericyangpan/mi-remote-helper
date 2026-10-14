import Foundation

/// Bluetooth Battery Level Status (2BED), BAS 1.1.
struct RemoteBatteryStatus: Equatable {
    let isCharging: Bool?
    let percentage: Int?

    init?(data: Data) {
        let bytes = Array(data)
        guard bytes.count >= 3 else { return nil }
        let flags = bytes[0]
        guard flags & 0xF8 == 0 else { return nil }
        let hasIdentifier = flags & 1 != 0
        let hasLevel = flags & 2 != 0
        let hasAdditionalStatus = flags & 4 != 0
        let expectedLength = 3 + (hasIdentifier ? 2 : 0)
            + (hasLevel ? 1 : 0) + (hasAdditionalStatus ? 1 : 0)
        guard bytes.count == expectedLength else { return nil }
        let powerState = UInt16(bytes[1]) | UInt16(bytes[2]) << 8
        let chargeState = (powerState >> 5) & 3
        isCharging = powerState & 1 == 0 || chargeState == 0 ? nil : chargeState == 1
        if hasLevel {
            let value = bytes[3 + (hasIdentifier ? 2 : 0)]
            guard value <= 100 || value == 255 else { return nil }
            percentage = value == 255 ? nil : Int(value)
        } else {
            percentage = nil
        }
    }
}
