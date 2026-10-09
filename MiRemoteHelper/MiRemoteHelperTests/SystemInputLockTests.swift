import Foundation
import Testing
@testable import MiRemoteHelper

struct SystemInputLockTests {
    @Test func failedRestorationRetriesWithoutRestartingItsBudget() {
        let f = RestorationFixture()
        #expect(f.lock.lock(to: "virtual"))
        f.lock.unlock()
        #expect(f.current == "virtual" && f.originalWrites == 1)
        #expect(f.lock.restorationError != nil)
        for _ in 0..<10 { f.lock.unlock() }
        #expect(f.originalWrites == 1 && f.pending.count == 1)
        f.failRestore = false
        f.runNext()
        #expect(f.current == "original" && f.originalWrites == 2)
        #expect(f.lock.restorationError == nil && f.pending.isEmpty)
    }

    @Test func persistentFailureIsBoundedAndExternalChoiceIsPreserved() {
        let f = RestorationFixture()
        #expect(f.lock.lock(to: "virtual"))
        f.lock.unlock()
        for _ in 0..<3 { f.runNext() }
        #expect(f.originalWrites == 4 && f.pending.isEmpty)
        #expect(f.lock.restorationError == String(localized: "Unable to restore the previous audio input. Select an input in Sound settings."))
        f.current = "external"
        f.lock.unlock()
        #expect(f.current == "external" && f.lock.restorationError == nil)
    }

    @Test func reconnectCancelsOldRetryAndKeepsOriginalInput() {
        let f = RestorationFixture()
        #expect(f.lock.lock(to: "virtual"))
        f.lock.unlock()
        #expect(f.lock.lock(to: "second-virtual"))
        f.failRestore = false
        f.runNext() // Deliberately invoke a cancelled work item.
        #expect(f.current == "second-virtual" && f.originalWrites == 1)
        f.lock.unlock()
        #expect(f.current == "original" && f.originalWrites == 2)
    }

    @Test func reconnectDuringUnavailableReadRetainsTheOriginalInput() {
        let f = RestorationFixture()
        #expect(f.lock.lock(to: "virtual"))
        f.lock.unlock()
        f.current = nil
        #expect(f.lock.lock(to: "second-virtual"))
        f.failRestore = false
        f.runNext()
        #expect(f.current == "second-virtual")
        f.lock.unlock()
        #expect(f.current == "original")
    }

    @Test func pendingRetryDoesNotOverwriteAnExternalSelection() {
        let f = RestorationFixture()
        #expect(f.lock.lock(to: "virtual"))
        f.lock.unlock()
        f.current = "external"
        f.failRestore = false
        f.runNext()
        #expect(f.current == "external" && f.originalWrites == 1)
        #expect(f.lock.restorationError == nil)
    }

    @Test func successRequiresReadbackAndTemporaryReadFailureRetainsState() {
        let f = RestorationFixture()
        #expect(f.lock.lock(to: "virtual"))
        f.reportSuccessWithoutWrite = true
        f.lock.unlock()
        #expect(f.current == "virtual" && f.lock.restorationError != nil)
        f.current = nil
        f.runNext()
        #expect(f.pending.count == 1)
        f.current = "virtual"
        f.reportSuccessWithoutWrite = false
        f.failRestore = false
        f.runNext()
        #expect(f.current == "original" && f.lock.restorationError == nil)
    }

    @Test func inputPolicyDefaultsOnAndPersistsAnExplicitOptOut() throws {
        let domain = "SystemInputLockTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.keepSystemInput)
        settings.keepSystemInput = false
        #expect(!AppSettings(defaults: defaults).keepSystemInput)
        settings.keepSystemInput = true
        #expect(AppSettings(defaults: defaults).keepSystemInput)
    }

    @Test func headphonesCannotReplaceInputDuringConnection() {
        var current: String? = "built-in"
        var writes: [String] = []
        var notify: (() -> Void)?
        var cancelled = false
        let lock = SystemInputLock(read: { current }, write: { writes.append($0); current = $0; return true },
            observe: { notify = $0; return { cancelled = true } })
        #expect(lock.lock(to: "blackhole"))
        for input in ["airpods", "built-in", "airpods"] {
            current = input
            notify?()
            #expect(current == "blackhole")
        }
        let count = writes.count
        for _ in 0..<10 { #expect(lock.lock(to: "blackhole")) }
        #expect(writes.count == count) // Idle checks and our own notifications don't write.
        lock.unlock()
        #expect(cancelled && current == "built-in")
        current = "airpods"
        notify?() // Already-queued notification after stop.
        #expect(current == "airpods")
    }

    @Test func missingDeviceIsRetriedAndNeverReportedAsLocked() {
        var current: String? = "airpods"
        var available = false
        let lock = SystemInputLock(read: { current }, write: { uid in
            guard available else { return false }; current = uid; return true
        }, observe: { _ in {} })
        #expect(!lock.lock(to: "blackhole") && current == "airpods")
        available = true
        #expect(lock.lock(to: "blackhole") && current == "blackhole")
        lock.unlock()
        #expect(current == "airpods")
    }

    @Test func stopPreservesExternalChoiceAndReconfigureKeepsOriginalInput() {
        var current: String? = "original"
        let lock = SystemInputLock(read: { current }, write: { current = $0; return true }, observe: { _ in {} })
        #expect(lock.lock(to: "blackhole"))
        #expect(lock.lock(to: "miremote"))
        lock.unlock()
        #expect(current == "original")
        #expect(lock.lock(to: "blackhole"))
        current = "external-choice"
        lock.unlock()
        #expect(current == "external-choice")
    }

    @Test func successfulWriteWithoutReadbackIsNotSuccess() {
        let lock = SystemInputLock(read: { "airpods" }, write: { _ in true }, observe: { _ in {} })
        #expect(!lock.lock(to: "blackhole"))
        lock.unlock()
    }
}

private final class RestorationFixture {
    var current: String? = "original"
    var failRestore = true
    var reportSuccessWithoutWrite = false
    var originalWrites = 0
    var pending: [() -> Void] = []
    lazy var lock = SystemInputLock(read: { [weak self] in self?.current }, write: { [weak self] uid in
        guard let self else { return false }
        if uid == "original" {
            originalWrites += 1
            if reportSuccessWithoutWrite { return true }
            if failRestore { return false }
        }
        current = uid
        return true
    }, observe: { _ in {} }, scheduleRetry: { [weak self] callback in
        self?.pending.append(callback)
        return {} // Exercise generation protection even if cancellation is late.
    })
    func runNext() { if !pending.isEmpty { pending.removeFirst()() } }
}
