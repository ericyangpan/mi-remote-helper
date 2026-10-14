import Foundation
import Testing
@testable import MiRemoteHelper

struct RemoteBatteryStatusTests {
    @Test func distinguishesChargingDischargingAndUnknown() {
        #expect(RemoteBatteryStatus(data: Data([0, 0x21, 0]))?.isCharging == true)
        #expect(RemoteBatteryStatus(data: Data([0, 0x41, 0]))?.isCharging == false)
        #expect(RemoteBatteryStatus(data: Data([0, 0x61, 0]))?.isCharging == false)
        #expect(RemoteBatteryStatus(data: Data([0, 1, 0]))?.isCharging == nil)
        #expect(RemoteBatteryStatus(data: Data([0, 0x20, 0]))?.isCharging == nil)
    }

    @Test func parsesOptionalFieldsWithoutMistakingIdentifierForLevel() {
        #expect(RemoteBatteryStatus(data: Data([2, 0x21, 0, 62]))?.percentage == 62)
        #expect(RemoteBatteryStatus(data: Data([7, 0x21, 0, 255, 200, 100, 0]))?.percentage == 100)
        #expect(RemoteBatteryStatus(data: Data([2, 0x21, 0, 255]))?.percentage == nil)
        let storage = Data([255, 2, 0x21, 0, 0])
        #expect(RemoteBatteryStatus(data: storage.dropFirst())?.percentage == 0)
    }

    @Test func rejectsMalformedPackets() {
        for bytes: [UInt8] in [[], [0], [0, 0x21], [2, 0x21, 0],
                               [1, 0x21, 0, 0], [4, 0x21, 0],
                               [0, 0x21, 0, 100], [8, 0x21, 0], [2, 0x21, 0, 101]] {
            #expect(RemoteBatteryStatus(data: Data(bytes)) == nil)
        }
    }
}
