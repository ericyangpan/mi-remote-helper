import CoreGraphics
import Foundation
import Testing
@testable import MiRemoteHelper

@MainActor
struct BridgeRecoveryIntegrationTests {
    @Test(arguments: ["double", "hold", "single", "cancel", "disconnect"])
    func configurableVoiceDoublePressIsExclusive(outcome: String) throws {
        let f = try Fixture(mappingsEnabled: true)
        defer { f.close() }
        let tap = ButtonBinding.preset(.returnKey)
        let double = ButtonBinding.preset(.escape)
        #expect(f.model.buttons.setBinding(tap, for: .microphone))
        #expect(f.model.buttons.setBinding(double, for: .microphone, press: .doubleTap))
        for profile in f.model.buttons.applicationProfiles {
            f.model.buttons.setApplicationEnabled(false, profileID: profile.id)
        }
        f.connect()
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .down)
        f.now += 0.05
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .up)
        #expect(f.tapBindings.isEmpty && f.events.isEmpty)
        if outcome == "double" || outcome == "hold" {
            f.now += 0.1
            f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .down)
            f.now += outcome == "hold" ? 0.6 : 0.05
            f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .up)
        } else if outcome == "cancel" {
            f.model.cancelVoiceGestureForApplicationChange()
        } else if outcome == "disconnect" {
            f.model.bluetoothBridge(f.callbackBridge, didChange: .reconnecting)
        }
        f.now += 1
        f.model.flushVoiceTap()
        #expect(f.tapBindings == (outcome == "double" ? [double] : outcome == "single" ? [tap] : []))
        #expect(outcome == "hold" ? !f.events.isEmpty : f.events.isEmpty)
    }

    @Test(arguments: [VoiceKey.fn, .leftControl])
    func shortVoicePressNeverStartsDictation(key: VoiceKey) throws {
        let f = try Fixture(key: key)
        defer { f.close() }
        f.connect()
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .down)
        f.model.bluetoothBridgeDidStartVoice(f.callbackBridge)
        f.model.bluetoothBridge(f.callbackBridge, didDecode: [100, 200])
        #expect(f.events.isEmpty && !f.model.isSpeaking && f.model.sampleCount == 0)
        f.now += 0.1
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .up)
        f.now += 1
        f.model.activatePendingVoiceHold()
        f.model.bluetoothBridgeDidStopVoice(f.callbackBridge)
        #expect(f.events.isEmpty && !f.model.isVoiceKeyHeld)
        #expect(f.transport.reconnections == 0)
    }

    @Test(arguments: [VoiceKey.fn, .leftControl])
    func holdStartsAfterThresholdAndHandlesAnAlreadyStartedStream(key: VoiceKey) throws {
        let f = try Fixture(key: key)
        defer { f.close() }
        f.connect()
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .down)
        f.model.bluetoothBridgeDidStartVoice(f.callbackBridge)
        f.now += 0.49
        f.model.activatePendingVoiceHold()
        #expect(f.events.isEmpty)
        f.now += 0.02
        f.model.activatePendingVoiceHold()
        #expect(f.events.count == 2 && f.model.isSpeaking)
        f.model.bluetoothBridge(f.callbackBridge, didDecode: [100, 200])
        #expect(f.model.sampleCount > 0)
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .up)
        f.model.bluetoothBridgeDidStopVoice(f.callbackBridge)
        #expect(f.events.count == 4 && !f.model.isVoiceKeyHeld)
    }

    @Test(arguments: [VoiceKey.rightOption, .f20])
    func legacyKeysAlsoSeparateTapAndHeldDictation(key: VoiceKey) throws {
        let f = try Fixture(key: key)
        defer { f.close() }
        f.connect()
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .down)
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .up)
        #expect(f.events.isEmpty)
        f.press()
        f.model.bluetoothBridgeDidStartVoice(f.callbackBridge)
        #expect(f.events.count == 1 && f.model.isSpeaking)
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .up)
        f.model.bluetoothBridgeDidStopVoice(f.callbackBridge)
        #expect(f.events.count == 2 && !f.model.isVoiceKeyHeld)
    }

    @Test func disconnectCancelsPendingVoiceHold() throws {
        let f = try Fixture()
        defer { f.close() }
        f.connect()
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .down)
        f.model.bluetoothBridge(f.callbackBridge, didChange: .reconnecting)
        f.now += 1
        f.model.activatePendingVoiceHold()
        #expect(f.events.isEmpty && !f.model.isVoiceKeyHeld)
    }

    @Test func voiceTapUsesMappingWhileHoldAndCancellationNeverSendIt() throws {
        let f = try Fixture(mappingsEnabled: true)
        defer { f.close() }
        let binding = ButtonBinding.shortcut(KeyChord(keyCode: 34, keyLabel: "I", modifiers: [.command, .option]))
        #expect(f.model.buttons.setBinding(binding, for: .microphone))
        for profile in f.model.buttons.applicationProfiles {
            f.model.buttons.setApplicationEnabled(false, profileID: profile.id)
        }
        f.connect()
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .down)
        f.now += 0.1
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .up)
        #expect(f.tapBindings == [binding] && f.events.isEmpty)
        f.press()
        f.model.bluetoothBridgeDidStartVoice(f.callbackBridge)
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .up)
        f.model.bluetoothBridgeDidStopVoice(f.callbackBridge)
        #expect(f.tapBindings == [binding] && f.events.count == 4)
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .down)
        f.model.cancelVoiceGestureForApplicationChange()
        f.now += 1
        f.model.activatePendingVoiceHold()
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .up)
        #expect(f.tapBindings == [binding] && f.events.count == 4)
    }

    @Test func earlyTimerReschedulesAndOldCallbackCannotActivateAnotherPress() throws {
        let f = try Fixture()
        defer { f.close() }
        f.connect()
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .down)
        let old = f.model.pendingVoiceGeneration
        f.now += 0.49
        f.model.activatePendingVoiceHold(expectedGeneration: old)
        #expect(f.events.isEmpty && f.model.hasPendingVoiceTimer)
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .up)
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .down)
        f.now += 0.6
        f.model.activatePendingVoiceHold(expectedGeneration: old)
        #expect(f.events.isEmpty)
        f.model.activatePendingVoiceHold()
        #expect(f.events.count == 2)
    }

    @Test func repeatedDownDuringHoldOrCancellationNeverBecomesAShortPress() throws {
        let f = try Fixture(mappingsEnabled: true)
        defer { f.close() }
        f.connect()
        f.press()
        f.model.bluetoothBridgeDidStartVoice(f.callbackBridge)
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .down)
        f.now += 0.1
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .up)
        f.model.bluetoothBridgeDidStopVoice(f.callbackBridge)
        #expect(f.events.count == 4 && f.tapBindings.isEmpty)
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .down)
        f.model.cancelVoiceGestureForApplicationChange()
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .down)
        f.now += 1
        f.model.activatePendingVoiceHold()
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .up)
        #expect(f.events.count == 4 && f.tapBindings.isEmpty)
    }

    @Test func delayedTimerAtReleaseRunsOnlyHold() throws {
        let f = try Fixture(mappingsEnabled: true)
        defer { f.close() }
        f.connect()
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .down)
        f.model.bluetoothBridgeDidStartVoice(f.callbackBridge)
        f.now += 0.5
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .up)
        f.model.bluetoothBridgeDidStopVoice(f.callbackBridge)
        #expect(f.events.count == 4 && f.tapBindings.isEmpty)
        #expect(!f.model.hasPendingVoiceTimer)
    }

    @Test func preHoldAudioIsBoundedAndOnlyDeliveredForAHold() throws {
        let f = try Fixture()
        defer { f.close() }
        f.connect()
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .down)
        f.model.bluetoothBridgeDidStartVoice(f.callbackBridge)
        f.model.bluetoothBridge(f.callbackBridge, didDecode: Array(repeating: 100, count: 12_000))
        #expect(f.model.pendingVoiceSampleCount == 8_000 && f.output.samplesEnqueued == 0)
        f.now += 0.1
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .up)
        #expect(f.model.pendingVoiceSampleCount == 0 && f.output.samplesEnqueued == 0)
        f.model.bluetoothBridgeDidStopVoice(f.callbackBridge)
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .down)
        f.model.bluetoothBridgeDidStartVoice(f.callbackBridge)
        f.model.bluetoothBridge(f.callbackBridge, didDecode: [1, 2, 3])
        f.now += 0.5
        f.model.activatePendingVoiceHold()
        #expect(f.output.samplesEnqueued == 3 && f.model.pendingVoiceSampleCount == 0)
    }

    @Test func oldAudioDrainCannotCancelTheNextShortPress() throws {
        let f = try Fixture(mappingsEnabled: true)
        defer { f.close() }
        f.connect()
        f.press()
        f.model.bluetoothBridgeDidStartVoice(f.callbackBridge)
        f.output.queuedFrames = 100
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .up)
        f.model.bluetoothBridgeDidStopVoice(f.callbackBridge)
        let oldDrain = f.output.drainCompletion
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .down)
        let generation = f.model.pendingVoiceGeneration
        oldDrain?()
        #expect(f.model.pendingVoiceGeneration == generation && f.model.isVoiceKeyHeld)
        f.now += 0.1
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .up)
        #expect(f.events.count == 4 && f.tapBindings.count == 1)
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .up)
        #expect(f.tapBindings.count == 1)
    }

    @Test func configuredLaunchConnectsOnceAndManualStopStaysStopped() throws {
        let f = try Fixture()
        defer { f.close() }
        #expect(f.model.settings.connectAtLaunch)
        f.model.settings.peripheralIdentifier = UUID()
        f.model.startAtLaunchIfNeeded()
        #expect(f.model.isRunning && f.transport.starts == 1)
        f.model.startAtLaunchIfNeeded()
        #expect(f.transport.starts == 1)
        f.model.stop()
        f.model.startAtLaunchIfNeeded()
        f.model.checkHealth()
        #expect(!f.model.isRunning && f.transport.starts == 1)
        f.model.start()
        #expect(f.model.isRunning && f.transport.starts == 2)
    }

    @Test func launchRespectsDisabledPreferenceAndMissingSetup() throws {
        let f = try Fixture()
        defer { f.close() }
        f.model.startAtLaunchIfNeeded()
        #expect(!f.model.isRunning && f.transport.starts == 0)
        // Completing setup afterward must not silently start this run.
        f.model.settings.peripheralIdentifier = UUID()
        f.model.startAtLaunchIfNeeded()
        #expect(f.transport.starts == 0)
        let disabled = try Fixture()
        defer { disabled.close() }
        disabled.model.settings.peripheralIdentifier = UUID()
        disabled.model.settings.connectAtLaunch = false
        disabled.model.startAtLaunchIfNeeded()
        #expect(!disabled.model.isRunning && disabled.transport.starts == 0)
        #expect(!AppSettings(defaults: disabled.defaults).connectAtLaunch)
    }

    @Test func launchDoesNotRequestMissingBluetoothPermission() throws {
        let f = try Fixture(bluetoothAllowed: false)
        defer { f.close() }
        f.model.settings.peripheralIdentifier = UUID()
        f.model.startAtLaunchIfNeeded()
        #expect(!f.model.isRunning && f.transport.starts == 0)
    }

    @Test func launchWaitsForVirtualMicrophoneSetup() throws {
        let f = try Fixture()
        defer { f.close() }
        f.model.settings.peripheralIdentifier = UUID()
        f.model.settings.outputUID = ""
        f.model.startAtLaunchIfNeeded()
        #expect(!f.model.isRunning && f.transport.starts == 0)
    }
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
        // The physical release still arrives after recovery cancels the dictation session.
        f.model.bluetoothBridge(f.callbackBridge, didObserveVoiceKey: .up)
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

    @Test func transientVoiceMappingFailureRetriesWhileIdle() throws {
        let f = try Fixture()
        defer { f.close() }
        f.mapper.applySucceeds = false
        f.connect()
        #expect(!f.model.ready && !f.transport.enabled)
        let attempts = f.mapper.applies
        f.model.checkHealth()
        #expect(f.mapper.applies == attempts)
        f.mapper.applySucceeds = true
        f.now += 1.1
        f.model.checkHealth()
        #expect(f.model.ready && f.transport.enabled)
        #expect(f.mapper.applies == attempts + 1)
        f.press()
        f.model.bluetoothBridgeDidStartVoice(f.callbackBridge)
        f.model.bluetoothBridge(f.callbackBridge, didDecode: [100, 200])
        #expect(f.model.isSpeaking && f.model.isVoiceKeyHeld)
    }

    @Test func voiceMappingRestorationFailureRetriesAndStopCancelsRecovery() throws {
        let f = try Fixture()
        defer { f.close() }
        f.mapper.restoreSucceeds = false
        f.connect()
        #expect(!f.model.ready && !f.transport.enabled)
        f.mapper.restoreSucceeds = true
        f.now += 1.1
        f.model.checkHealth()
        #expect(f.model.ready)
        f.mapper.applySucceeds = false
        f.model.applySettings()
        f.model.stop()
        let attempts = f.mapper.applies
        f.now += 2
        f.model.checkHealth()
        #expect(f.mapper.applies == attempts && !f.transport.enabled)
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
    let mapper = FakeMapper()
    var events: [CGEvent] = []
    var tapBindings: [ButtonBinding] = []
    var now = 100.0
    var model: BridgeModel!
    var callbackBridge: XiaomiBluetoothBridge!
    init(key: VoiceKey = .fn, bluetoothAllowed: Bool = true, mappingsEnabled: Bool = false) throws {
        defaults = try #require(UserDefaults(suiteName: domain))
        defaults.set(mappingsEnabled, forKey: "buttonMappingEnabled")
        let settings = AppSettings(defaults: defaults)
        settings.voiceKey = key
        settings.outputUID = "fake-output"
        let voice = VoiceToggleShortcut(ambientFlags: { [] }, postEvent: { [weak self] in self?.events.append($0) },
            canStart: { true }, scheduleRelease: { $0() })
        model = BridgeModel(settings: settings, buttons: ButtonMappingModel(defaults: defaults,
            hasInputMonitoring: { false }, hasAccessibility: { true },
            sendBinding: { [weak self] binding in self?.tapBindings.append(binding); return true }),
            inputRoute: input, output: output, mapper: mapper, voiceToggle: voice,
            postLegacyEvent: { [weak self] in self?.events.append($0) },
            readPermissions: { BridgePermissions(inputMonitoring: true, accessibility: true, bluetooth: bluetoothAllowed) },
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
    func press() {
        model.bluetoothBridge(callbackBridge, didObserveVoiceKey: .down)
        now += ButtonPressTracker.holdDuration
        model.activatePendingVoiceHold()
    }
    func close() { model.stop(); defaults.removePersistentDomain(forName: domain) }
}

private final class FakeMapper: VoiceKeyMapping {
    var error: String?
    var applies = 0
    var applySucceeds = true
    var restoreSucceeds = true
    func apply(_ key: VoiceKey) -> Bool { applies += 1; return applySucceeds }
    func restore() -> Bool { restoreSucceeds }
}
private final class FakeTransport: RemoteVoiceTransport {
    var starts = 0
    var enabled = false
    var reconnections = 0
    var onReconnect: (() -> Void)?
    func start() { starts += 1 }
    func stop() { enabled = false }
    func reconnectNow() { reconnections += 1; onReconnect?() }
    func setVoiceBridgingEnabled(_ enabled: Bool) { self.enabled = enabled }
}
private final class FakeOutput: RemoteAudioRouting {
    var isReady = false
    var isDeviceAlive = true
    var deviceUID = ""
    var queuedFrames = 0
    var samplesEnqueued = 0
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
    func enqueue(_ samples: [Int16], completion: (() -> Void)?) -> Bool {
        if isReady { samplesEnqueued += samples.count }; return isReady
    }
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
