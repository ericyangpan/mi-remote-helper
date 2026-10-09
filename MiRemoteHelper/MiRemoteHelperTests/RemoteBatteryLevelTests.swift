import Foundation
import Testing
@testable import MiRemoteHelper

struct RemoteBatteryLevelTests {
    @Test func acceptsPercentageIncludingEmptyAndFullBattery() throws {
        for value: UInt8 in [0, 1, 20, 62, 99, 100] {
            let level = try #require(RemoteBatteryLevel(data: Data([value])))
            #expect(level.percentage == Int(value))
        }
    }

    @Test func rejectsMissingMalformedAndOutOfRangeReadings() {
        for data in [Data(), Data([62, 0]), Data([101]), Data([255])] {
            #expect(RemoteBatteryLevel(data: data) == nil)
        }
        let storage = Data([255, 62])
        #expect(RemoteBatteryLevel(data: storage.dropFirst())?.percentage == 62)
    }
}
