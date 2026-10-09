import CoreGraphics
import Foundation
import Testing
@testable import MiRemoteHelper

@MainActor
struct BridgeRecoveryIntegrationTests {
    @Test(arguments: [VoiceKey.fn, .leftControl])
    func hidChangesWaitForVoiceAndTailWithoutEndingDictation(key: VoiceKey) throws {
        let f = try Fixture(key: key)
        defer { f.close() }
        f.connect()
        let configurations = f.output.configurations
        f.press()
        f.model.bluetoothBridgeDidStartVoice(f.callbackBridge)
        f.model.buttons.onAvailabilityChange?()
        f.model.checkHealth()
        #expect(f.events.count == 2)
        #expect(f.model.isVoiceKeyHeld && f.model.isSpeaking && f.transport.enabled)
        #expect(f.output.configurations == configurations)
        f.output.queuedFrames = 240
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .up)
        f.model.bluetoothBridgeDidStopVoice(f.callbackBridge)
        f.model.checkHealth()
        #expect(f.events.count == 2 && f.output.configurations == configurations)
        f.output.drain()
        f.model.checkHealth()
        #expect(f.events.count == 4 && !f.model.isVoiceKeyHeld)
        #expect(f.output.configurations == configurations + 1 && f.model.ready)
    }

    @Test func hidChangesPreserveStartupWatchdog() throws {
        let f = try Fixture()
        defer { f.close() }
        f.connect()
        f.press()
        f.model.buttons.onAvailabilityChange?()
        f.now += 3
        f.model.checkHealth()
        #expect(f.transport.reconnections == 1)
        #expect(!f.model.isVoiceKeyHeld && !f.model.isSpeaking)
    }

    @Test func interruptedStreamStillTimesOutAfterHIDChange() throws {
        let f = try Fixture()
        defer { f.close() }
        f.connect()
        f.press()
        f.model.bluetoothBridgeDidStartVoice(f.callbackBridge)
        f.model.bluetoothBridge(f.callbackBridge, didDecode: [1, 2, 3])
        f.model.buttons.onAvailabilityChange?()
        f.now += 3
        f.model.checkHealth()
        #expect(f.transport.reconnections == 1)
        #expect(!f.model.isSpeaking && !f.model.isVoiceKeyHeld)
    }

    @Test func outputLossCancelsTestAndAllowsSettingsRecovery() throws {
        let f = try Fixture()
        defer { f.close() }
        f.connect()
        f.model.playTestTone()
        let stale = f.output.toneCompletion
        f.output.isDeviceAlive = false
        f.model.checkHealth()
        #expect(!f.model.testToneActive && !f.model.audioReady)
        f.model.applySettings()
        #expect(f.model.ready)
        f.model.playTestTone()
        stale?()
        #expect(f.model.testToneActive)
        f.output.toneCompletion?()
        #expect(!f.model.testToneActive)
    }

    @Test func testToneWithoutConnectionHasTimeoutAndCanRetry() async throws {
        let f = try Fixture()
        defer { f.close() }
        f.model.playTestTone()
        #expect(f.model.testToneActive && !f.model.isRunning)
        try await Task.sleep(for: .milliseconds(2200))
        #expect(!f.model.testToneActive && !f.model.audioReady)
        #expect(f.model.testToneMessage != nil)
        f.model.playTestTone()
        #expect(f.model.testToneActive && f.model.audioReady)
        f.output.toneCompletion?()
    }

    @Test func startingVoiceCancelsToneAndRejectsItsLateCompletion() throws {
        let f = try Fixture()
        defer { f.close() }
        f.connect()
        f.model.playTestTone()
        let stale = f.output.toneCompletion
        f.press()
        f.model.bluetoothBridgeDidStartVoice(f.callbackBridge)
        stale?()
        #expect(!f.model.testToneActive && f.model.testToneMessage == nil)
        #expect(f.model.isSpeaking && f.model.isVoiceKeyHeld)
    }

    @Test func audioEngineRouteChangeKeepsDictationSessionAndShortcut() throws {
        let f = try Fixture()
        defer { f.close() }
        f.connect()
        #expect(f.input.target == "fake-output")
        f.press()
        f.model.bluetoothBridgeDidStartVoice(f.callbackBridge)
        let configurations = f.output.configurations
        f.output.isReady = false // Headphone route change stopped the engine.
        f.input.onChange?()
        #expect(f.output.configurations == configurations + 1)
        #expect(f.events.count == 2 && f.model.isSpeaking && f.model.isVoiceKeyHeld && f.model.ready)
        f.model.bluetoothBridge(f.callbackBridge, didDecode: [1, 2, 3])
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .up)
        f.model.bluetoothBridgeDidStopVoice(f.callbackBridge)
        #expect(f.events.count == 4)
        f.model.stop()
        #expect(f.input.target == nil)
    }

    @Test func failedAudioRebuildRetriesWithoutManualReconnect() throws {
        let f = try Fixture()
        defer { f.close() }
        f.connect()
        f.press()
        f.model.bluetoothBridgeDidStartVoice(f.callbackBridge)
        f.output.configurationSucceeds = false
        f.output.isReady = false
        f.model.checkHealth()
        #expect(!f.model.ready && !f.model.isSpeaking && !f.model.isVoiceKeyHeld)
        #expect(f.events.count == 4)
        f.output.configurationSucceeds = true
        f.now += 2
        f.model.checkHealth()
        #expect(f.model.ready && f.transport.reconnections == 0)
        f.press()
        #expect(f.events.count == 6)
    }

    @Test func disabledInputLockDoesNotChangeSystemInputOrBlockVoice() throws {
        let f = try Fixture()
        defer { f.close() }
        f.model.settings.keepSystemInput = false
        f.input.available = false
        f.connect()
        f.model.checkHealth()
        f.press()
        f.model.bluetoothBridgeDidStartVoice(f.callbackBridge)
        // Engine recovery stays enabled even though system input is unmanaged.
        f.output.isReady = false
        f.model.checkHealth()
        #expect(f.input.lockCalls == 0 && f.input.target == nil)
        #expect(f.model.ready && f.model.isSpeaking && f.events.count == 2)
    }

    @Test func disablingReleasesLockAndReenablingUsesSelectedDevice() throws {
        let f = try Fixture()
        defer { f.close() }
        f.connect()
        #expect(f.input.target == "fake-output")
        f.model.settings.keepSystemInput = false
        f.model.applySettings()
        let calls = f.input.lockCalls
        f.model.checkHealth()
        f.press()
        #expect(f.input.target == nil && f.input.lockCalls == calls && f.model.ready)
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .up)
        f.model.settings.outputUID = "another-virtual-device"
        f.model.settings.keepSystemInput = true
        f.model.applySettings()
        #expect(f.input.target == "another-virtual-device" && f.model.ready)
    }

    @Test func nextVoicePressDoesNotApplyPendingHIDSettingsInsideControlCallback() throws {
        let f = try Fixture()
        defer { f.close() }
        f.connect()
        f.press()
        f.model.buttons.onAvailabilityChange?()
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .up)
        let configurations = f.output.configurations
        f.press()
        #expect(f.output.configurations == configurations)
        #expect(f.model.isVoiceKeyHeld && f.events.count == 6)
    }

    @Test func unavailableSystemInputCannotActivateDictationBeforeNotification() throws {
        let f = try Fixture()
        defer { f.close() }
        f.connect()
        f.input.available = false
        f.press()
        #expect(f.events.isEmpty && !f.model.isVoiceKeyHeld && !f.model.ready)
    }

    @Test func inputDeviceReturnAutomaticallyRestoresVoiceReadiness() throws {
        let f = try Fixture()
        defer { f.close() }
        f.input.available = false
        f.connect()
        #expect(!f.model.ready && !f.transport.enabled)
        f.input.available = true
        f.now += 2
        f.input.onChange?()
        #expect(f.model.ready && f.transport.enabled)
        f.model.bluetoothBridge(f.callbackBridge, didChange: .reconnecting)
        #expect(f.input.target == nil && !f.model.ready)
    }

    @Test func inputRestorationFailureRemainsVisibleAfterStopAndClearsOnRecovery() throws {
        let f = try Fixture()
        defer { f.close() }
        f.connect()
        f.input.restorationError = "Restoration failed"
        f.model.stop()
        #expect(f.model.statusMessage == "Restoration failed")
        let count = f.output.configurations
        f.input.restorationError = nil
        f.input.onChange?()
        #expect(f.model.inputRestorationError == nil)
        #expect(f.model.statusMessage == f.model.message)
        #expect(!f.model.isRunning && f.output.configurations == count)
    }

    @Test func stoppingWhileReconfigurationPendingDoesNotRestartAudio() throws {
        let f = try Fixture()
        defer { f.close() }
        f.connect()
        f.press()
        f.model.buttons.onAvailabilityChange?()
        let count = f.output.configurations
        f.model.stop()
        f.model.checkHealth()
        #expect(f.output.configurations == count)
        #expect(!f.model.ready && !f.model.isVoiceKeyHeld)
    }
}

private final class Fixture {
    let domain = "BridgeRecoveryIntegrationTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let input = FakeInputRoute()
    let output = FakeOutput()
    let transport = FakeTransport()
    var events: [CGEvent] = []
    var now = 100.0
    var model: BridgeModel!
    var callbackBridge: XiaomiBluetoothBridge!
    init(key: VoiceKey = .fn) throws {
        defaults = try #require(UserDefaults(suiteName: domain))
        let settings = AppSettings(defaults: defaults)
        settings.voiceKey = key
        settings.outputUID = "fake-output"
        let voice = VoiceToggleShortcut(ambientFlags: { [] }, postEvent: { [weak self] in self?.events.append($0) },
            canStart: { true }, scheduleRelease: { $0() })
        model = BridgeModel(settings: settings, buttons: ButtonMappingModel(defaults: defaults),
            inputRoute: input, output: output, mapper: FakeMapper(), voiceToggle: voice,
            readPermissions: { BridgePermissions(inputMonitoring: true, accessibility: true, bluetooth: true) },
            listDevices: { [AudioDeviceInfo(id: 1, uid: "fake-output", name: "Fake Output")] },
            uptime: { [weak self] in self?.now ?? 0 }, makeTransport: { [transport] _, _ in transport })
        callbackBridge = XiaomiBluetoothBridge(settings: settings, delegate: model)
        transport.onReconnect = { [weak self] in
            guard let self else { return }
            self.model.bluetoothBridge(self.callbackBridge, didChange: .reconnecting)
        }
    }
    func connect() {
        model.start()
        model.bluetoothBridge(callbackBridge, didChange: .ready("Test remote"))
    }
    func press() { model.bluetoothBridge(callbackBridge, didObserveVoiceKey: .down) }
    func close() { model.stop(); defaults.removePersistentDomain(forName: domain) }
}

private final class FakeMapper: VoiceKeyMapping {
    var error: String?
    func apply(_ key: VoiceKey) -> Bool { true }
    func restore() -> Bool { true }
}
private final class FakeTransport: RemoteVoiceTransport {
    var enabled = false
    var reconnections = 0
    var onReconnect: (() -> Void)?
    func start() {}
    func stop() { enabled = false }
    func reconnectNow() { reconnections += 1; onReconnect?() }
    func setVoiceBridgingEnabled(_ enabled: Bool) { self.enabled = enabled }
}
private final class FakeOutput: RemoteAudioRouting {
    var isReady = false
    var isDeviceAlive = true
    var deviceUID = ""
    var queuedFrames = 0
    var error: String?
    var configurations = 0
    var configurationSucceeds = true
    var toneCompletion: (() -> Void)?
    var drainCompletion: (() -> Void)?
    func configure(uid: String) -> Bool {
        stop(); configurations += 1
        guard configurationSucceeds else { return false }
        deviceUID = uid; isReady = true; isDeviceAlive = true
        return true
    }
    func stop() { isReady = false; deviceUID = ""; beginSession() }
    func beginSession() { queuedFrames = 0; toneCompletion = nil; drainCompletion = nil }
    func enqueue(_ samples: [Int16], completion: (() -> Void)?) -> Bool { isReady }
    func testTone(completion: @escaping () -> Void) -> Bool {
        beginSession(); toneCompletion = completion; queuedFrames = 8000; return isReady
    }
    func whenDrained(_ completion: @escaping () -> Void) {
        if queuedFrames == 0 { completion() } else { drainCompletion = completion }
    }
    func drain() { queuedFrames = 0; let completion = drainCompletion; drainCompletion = nil; completion?() }
}

private final class FakeInputRoute: SystemInputRouting {
    var restorationError: String?
    var onChange: (() -> Void)?
    var available = true
    var target: String?
    var lockCalls = 0
    func lock(to uid: String) -> Bool { lockCalls += 1; target = uid; return available }
    func unlock() { target = nil }
}
