import Foundation
import Testing
@testable import MiRemoteHelper

@MainActor
struct MappingRestorationTests {
    @Test func failedStopRetainsReaderAndRetriesEvenWhenMappingIsOff() throws {
        let domain = "MappingRestorationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let reader = FailingReader()
        var creations = 0
        let model = ButtonMappingModel(defaults: defaults, makeReader: { creations += 1; return reader },
                                       hasInputMonitoring: { true }, hasAccessibility: { true })
        model.setEnabled(true)
        model.refresh(connected: true)
        #expect(model.active)
        model.setEnabled(false)
        #expect(!model.active && !model.enabled && model.restorationError != nil)
        let error = model.status
        model.refresh(connected: false)
        #expect(model.status == error) // Must not claim "off" or "disconnected" yet.
        model.retryPendingRestoration()
        #expect(reader.stops == 2 && model.restorationError != nil)
        reader.restoreSucceeds = true
        model.retryPendingRestoration()
        #expect(reader.stops == 3 && model.restorationError == nil)
        #expect(creations == 1 && !model.active)
    }

    @Test func removalFailureRetriesAutomaticallyAfterDisconnect() async throws {
        let domain = "MappingRestorationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let reader = FailingReader()
        let model = ButtonMappingModel(defaults: defaults, makeReader: { reader },
            hasInputMonitoring: { true }, hasAccessibility: { true })
        model.setEnabled(true)
        model.refresh(connected: true)
        var changes = 0
        model.onAvailabilityChange = { changes += 1 }
        reader.restorationPending = true
        reader.onActive?(false, nil)
        #expect(!model.active && model.restorationError != nil && changes == 1)
        model.refresh(connected: false)
        reader.restoreSucceeds = true
        try await Task.sleep(for: .milliseconds(1200))
        #expect(reader.stops >= 2 && model.restorationError == nil && !model.active)
    }

    @Test func reenableCannotOverwriteOriginalsWhileRestorationIsPending() throws {
        let domain = "MappingRestorationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let old = FailingReader()
        let fresh = FailingReader()
        fresh.restoreSucceeds = true
        var creations = 0
        let model = ButtonMappingModel(defaults: defaults, makeReader: {
            creations += 1; return creations == 1 ? old : fresh
        }, hasInputMonitoring: { true }, hasAccessibility: { true })
        model.setEnabled(true)
        model.refresh(connected: true)
        model.setEnabled(false)
        model.setEnabled(true)
        #expect(creations == 1 && !model.active)
        old.restoreSucceeds = true
        model.retryPendingRestoration()
        #expect(creations == 2 && model.active && model.restorationError == nil)
        model.setEnabled(false)
    }
}

private final class FailingReader: RemoteButtonReading {
    var onActive: ((Bool, String?) -> Void)?
    var onReport: ((Set<UInt16>) -> Void)?
    var restorationPending = false
    var restoreSucceeds = false
    var stops = 0
    func start() { onActive?(true, nil) }
    func stop() -> Bool {
        stops += 1; restorationPending = !restoreSucceeds; return restoreSucceeds
    }
}
