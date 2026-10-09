import Combine
import Foundation
import Testing
@testable import MiRemoteHelper

struct IdlePerformanceTests {
    @Test func unchangedPermissionsAndDevicesDoNotInvalidateViews() {
        let model = BridgeModel()
        model.refreshPermissions()
        model.refreshDevices()
        var updates = 0
        let observation = model.objectWillChange.sink { updates += 1 }
        model.refreshPermissions()
        model.refreshDevices()
        #expect(updates == 0)
        withExtendedLifetime(observation) {}
    }

    @Test func idleDisabledMappingsDoNotInvalidateViews() throws {
        let name = "IdlePerformanceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = ButtonMappingModel(defaults: defaults)
        model.refresh(connected: false)
        var updates = 0
        let observation = model.objectWillChange.sink { updates += 1 }
        for _ in 0..<10 { model.refresh(connected: false) }
        #expect(updates == 0)
        withExtendedLifetime(observation) {}
    }

    @Test func meterRetainsExactDurationBetweenPresentationUpdates() {
        var meter = AudioInputMeter()
        meter.append(Array(repeating: 123, count: 128))
        meter.clearPeak()
        meter.append(Array(repeating: 456, count: 256))
        #expect(meter.sampleCount == 384)
        meter.clearPeak()
        #expect(meter.sampleCount == 384)
        meter = AudioInputMeter()
        #expect(meter.sampleCount == 0)
    }
}
