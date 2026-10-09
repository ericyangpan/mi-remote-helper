import Foundation
import Testing
import CoreGraphics
import IOKit.hidsystem
import CoreBluetooth
@testable import MiRemoteHelper

struct MiRemoteHelperTests {
    @Test func bluetoothStartupDisplaysAuthorizationBeforeAnyCallback() {
        #expect(BluetoothBridgeState.initialState(authorization: .notDetermined) == .awaitingBluetoothPermission)
        #expect(BluetoothBridgeState.initialState(authorization: .allowedAlways) == .initializingBluetooth)
        #expect(BluetoothBridgeState.initialState(authorization: .denied) == .bluetoothUnavailable(String(localized: "Bluetooth permission not granted")))
        #expect(BluetoothBridgeState.initialState(authorization: .restricted) == .bluetoothUnavailable(String(localized: "Bluetooth access restricted by the system")))
    }
    @Test func rejectsMalformedOrUnsupportedCapabilities() {
        #expect(ATVVCapabilities.parse(Data()) == nil)
        #expect(ATVVCapabilities.parse(Data([0x0B, 1, 0, 1, 3, 0, 120])) == nil)
        #expect(ATVVCapabilities.parse(Data([0x0B, 1, 0, 2, 3, 0xFF, 0xFF])) == nil)
        let caps = ATVVCapabilities.parse(Data([0x0B, 1, 0, 2, 3, 0, 120]))
        #expect(caps?.sampleRate == 16_000)
        #expect(caps?.frameSize == 120)
    }

    @Test func decoderUsesHighNibbleFirstAndCarriesStateAcrossPackets() {
        let decoder = IMAADPCMDecoder()
        #expect(decoder.decode(Data([0x17])) == [1, 12])
        let whole = IMAADPCMDecoder().decode(Data([0x17, 0xAB, 0x42]))
        decoder.reset()
        let split = decoder.decode(Data([0x17])) + decoder.decode(Data([0xAB, 0x42]))
        #expect(split == whole)
    }

    @Test func decoderSyncClampsAndResetsPredictor() {
        let decoder = IMAADPCMDecoder()
        decoder.reset(predictor: 999_999, stepIndex: 999)
        #expect(decoder.predictor == 32_767)
        #expect(decoder.stepIndex == 88)
        #expect(decoder.decode(Data([0x77])) == [32_767, 32_767])
        decoder.reset(predictor: -999_999, stepIndex: -1)
        #expect(decoder.predictor == -32_768)
        #expect(decoder.stepIndex == 0)
        decoder.reset()
        #expect(decoder.decode(Data([0x17])) == [1, 12])
    }

    @Test func packetFragmentsAreNotDroppedOrMixedAcrossSessions() {
        var buffer = FrameAccumulator()
        #expect(buffer.append(Data([1, 2]), frameSize: 3).isEmpty)
        #expect(buffer.append(Data([3, 4, 5, 6, 7]), frameSize: 3) == [Data([1, 2, 3]), Data([4, 5, 6])])
        buffer.reset()
        #expect(buffer.append(Data([8, 9, 10]), frameSize: 3) == [Data([8, 9, 10])])
    }

    @Test func staleBluetoothCallbacksCannotOpenMicrophone() {
        #expect(!ATVVSessionGate.canOpenMicrophone(phase: .ready(2), generation: 1, capabilitiesConfirmed: true, sampleRate: 16_000))
        #expect(!ATVVSessionGate.canOpenMicrophone(phase: .awaitingCapabilities(2), generation: 2, capabilitiesConfirmed: true, sampleRate: 16_000))
        #expect(!ATVVSessionGate.canOpenMicrophone(phase: .ready(2), generation: 2, capabilitiesConfirmed: false, sampleRate: 16_000))
        #expect(ATVVSessionGate.canOpenMicrophone(phase: .ready(2), generation: 2, capabilitiesConfirmed: true, sampleRate: 16_000))
    }

    @Test func unknownRemoteModelsAreRejected() {
        var gate = XiaomiModelConfirmationGate()
        #expect(gate.accept("RC001") == nil)
        #expect(!gate.isConfirmed)
        #expect(gate.accept(" RC003\n") != nil)
        #expect(gate.isConfirmed)
        #expect(gate.accept("RC003") == nil)
    }

    @Test func mappingChangesOnlyMicrophoneAndRestoresPreviousChoice() {
        let unrelated = KeyMapping(source: 0x700000004, destination: 0x700000005)
        let originalVoice = KeyMapping(source: KeyMapping.microphone, destination: VoiceKey.f20.hidUsage)
        let original = [unrelated, originalVoice]
        let mapped = KeyMapping.replacingVoice(in: original, with: VoiceKey.leftControl.hidUsage)
        #expect(mapped == [unrelated, KeyMapping(source: KeyMapping.microphone, destination: 0x7000000E0)])
        #expect(KeyMapping.replacingVoice(in: mapped, with: originalVoice.destination) == original)
        #expect(KeyMapping.replacingVoice(in: mapped, with: nil) == [unrelated])
    }

    @Test func cancelledPressDrainsWithoutAnExtraRelease() {
        var tracker = RemoteVoiceControlEdgeTracker()
        #expect(tracker.update(active: true) == .down)
        #expect(tracker.update(active: true) == nil)
        tracker.cancelCurrentPress()
        #expect(tracker.update(active: false) == nil)
        #expect(tracker.update(active: true) == .down)
        #expect(tracker.update(active: false) == .up)
    }

    @Test func defaultShortcutIsUsersLeftControl() {
        let suite = "mi-helper-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.voiceKey == .leftControl)
        settings.voiceKey = .f20
        #expect(AppSettings(defaults: defaults).voiceKey == .f20)
    }

    @Test func voiceShortcutOwnsOneBalancedPair() {
        var events: [Bool] = []
        let shortcut = HeldVoiceShortcut { events.append($0); return true }
        #expect(shortcut.release()) // A late STOP must not inject an orphan release.
        #expect(shortcut.press())
        #expect(shortcut.press()) // MIC_OPEN and STREAM_START may describe one press.
        #expect(shortcut.isHeld)
        #expect(shortcut.release())
        #expect(shortcut.release())
        #expect(!shortcut.isHeld)
        #expect(events == [true, false])
        #expect(shortcut.press())
        #expect(shortcut.release())
        #expect(events == [true, false, true, false])
    }

    @Test func failedKeyDeliveryDoesNotLoseReleaseOwnership() {
        var succeeds = false
        var events: [Bool] = []
        let shortcut = HeldVoiceShortcut { events.append($0); return succeeds }
        #expect(!shortcut.press())
        #expect(!shortcut.isHeld)
        succeeds = true
        #expect(shortcut.press())
        succeeds = false
        #expect(!shortcut.release())
        #expect(shortcut.isHeld)
        succeeds = true
        #expect(shortcut.release())
        #expect(!shortcut.isHeld)
        #expect(events == [true, true, false, false])
    }

    @Test func oldAudioDrainCannotReleaseANewVoicePress() {
        var events: [Bool] = []
        let shortcut = HeldVoiceShortcut { events.append($0); return true }
        #expect(shortcut.press())
        let oldSession = shortcut.generation
        #expect(shortcut.release())
        #expect(shortcut.press())
        #expect(shortcut.release(ifGeneration: oldSession))
        #expect(shortcut.isHeld)
        #expect(events == [true, false, true])
        #expect(shortcut.release(ifGeneration: shortcut.generation))
        #expect(events == [true, false, true, false])
    }

    @Test func quickVoiceStopQueuesASecondCompleteControlTap() {
        var callbacks: [() -> Void] = []
        var events: [String] = []
        let taps = ControlTapSequencer { callbacks.append($0) }
        let session = HeldVoiceShortcut { starting in
            let phase = starting ? "start" : "end"
            return taps.enqueue((down: { events.append(phase + ".down") }, up: { events.append(phase + ".up") }))
        }
        #expect(session.press())
        #expect(session.press())
        #expect(session.release())
        #expect(session.release())
        #expect(events == ["start.down"])
        callbacks.removeFirst()()
        #expect(events == ["start.down", "start.up", "end.down"])
        callbacks.removeFirst()()
        #expect(events == ["start.down", "start.up", "end.down", "end.up"])
    }

    @Test func terminationFinishesQueuedTapsAndIgnoresOldTimers() {
        var callbacks: [() -> Void] = []
        var events: [Bool] = []
        let taps = ControlTapSequencer { callbacks.append($0) }
        let tap = (down: { events.append(true) }, up: { events.append(false) })
        #expect(taps.enqueue(tap))
        #expect(taps.enqueue(tap))
        taps.finishImmediately()
        #expect(events == [true, false, true, false])
        #expect(taps.enqueue(tap))
        callbacks.removeFirst()() // Prior session's scheduled release.
        #expect(events == [true, false, true, false, true])
        callbacks.removeFirst()()
        #expect(events == [true, false, true, false, true, false])
    }

    @Test func leftControlEmitsModifierTransitionsAndPreservesOtherModifiers() throws {
        let source = try #require(CGEventSource(stateID: .privateState))
        let down = try #require(VoiceToggleShortcut.event(source: source, down: true, ambientFlags: .maskShift))
        let up = try #require(VoiceToggleShortcut.event(source: source, down: false, ambientFlags: .maskShift))
        #expect(down.type == .flagsChanged)
        #expect(up.type == .flagsChanged)
        #expect(down.getIntegerValueField(.keyboardEventKeycode) == 59)
        #expect(up.getIntegerValueField(.keyboardEventKeycode) == 59)
        #expect(down.flags.contains(.maskControl))
        #expect(down.flags.rawValue & UInt64(NX_DEVICELCTLKEYMASK) != 0)
        #expect(up.flags == .maskShift)
        let physicalControl = CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | UInt64(NX_DEVICERCTLKEYMASK))
        let overlappingRelease = try #require(VoiceToggleShortcut.event(source: source, down: false, ambientFlags: physicalControl))
        #expect(overlappingRelease.flags == physicalControl)
    }

    @Test func suppressingNativeVoiceKeyPreservesOtherMappingsAndRestoresOriginal() {
        let other = KeyMapping(source: 0x700000004, destination: 0x700000005)
        let original = KeyMapping(source: KeyMapping.microphone, destination: VoiceKey.f20.hidUsage)
        let suppressed = KeyMapping.replacingVoice(in: [other, original], with: 0)
        #expect(suppressed == [other, KeyMapping(source: KeyMapping.microphone, destination: 0)])
        #expect(KeyMapping.replacingVoice(in: suppressed, with: original.destination) == [other, original])
    }

    @Test func fnToggleEmitsBalancedModifierEdgesWithoutControl() throws {
        let source = try #require(CGEventSource(stateID: .privateState))
        let down = try #require(VoiceToggleShortcut.event(source: source, down: true, ambientFlags: .maskShift, key: .fn))
        let up = try #require(VoiceToggleShortcut.event(source: source, down: false, ambientFlags: .maskShift, key: .fn))
        #expect(down.type == .flagsChanged)
        #expect(up.type == .flagsChanged)
        #expect(down.getIntegerValueField(.keyboardEventKeycode) == 63)
        #expect(up.getIntegerValueField(.keyboardEventKeycode) == 63)
        #expect(down.flags == [.maskShift, .maskSecondaryFn])
        #expect(up.flags == .maskShift)
        #expect(down.getIntegerValueField(.eventSourceUserData) == VoiceEventDiagnostics.marker)
        let physicalFn: CGEventFlags = [.maskShift, .maskSecondaryFn]
        let release = try #require(VoiceToggleShortcut.event(source: source, down: false, ambientFlags: physicalFn, key: .fn))
        #expect(release.flags == .maskShift)
        #expect(VoiceToggleShortcut.event(source: source, down: true, ambientFlags: [], key: .f20) == nil)
    }

    @Test func rapidVoiceSessionsCannotLatchTheirOwnModifier() {
        for key in [VoiceKey.fn, .leftControl] {
            var callbacks: [() -> Void] = []
            var ambient: CGEventFlags = []
            var delivered: [CGEventFlags] = []
            let shortcut = VoiceToggleShortcut(ambientFlags: { ambient }, postEvent: { event in
                // Model HID state reflecting the last synthetic event, as in the incident.
                ambient = event.flags
                delivered.append(event.flags)
            }, canStart: { true }, scheduleRelease: { callbacks.append($0) })
            for _ in 0..<4 {
                #expect(shortcut.press(key: key))
                #expect(shortcut.release())
            }
            #expect(delivered.count == 1) // All other taps queued behind the first down.
            while !callbacks.isEmpty { callbacks.removeFirst()() }
            #expect(delivered.count == 16)
            let mask: CGEventFlags = key == .fn ? .maskSecondaryFn : .maskControl
            for (index, flags) in delivered.enumerated() {
                #expect(flags.contains(mask) == (index % 2 == 0))
                if index % 2 == 1 { #expect(flags.isEmpty) }
            }
            #expect(ambient.isEmpty)
            #expect(!shortcut.isHeld)
        }
    }

    @Test func queuedVoiceEdgesUseCurrentUnrelatedModifiers() {
        var callbacks: [() -> Void] = []
        var ambient: CGEventFlags = .maskShift
        var delivered: [CGEventFlags] = []
        let shortcut = VoiceToggleShortcut(ambientFlags: { ambient }, postEvent: { event in
            ambient = event.flags
            delivered.append(event.flags)
        }, canStart: { true }, scheduleRelease: { callbacks.append($0) })
        #expect(shortcut.press(key: .fn))
        #expect(shortcut.release())
        ambient.remove(.maskShift) // The user releases Shift while a tap is queued.
        ambient.insert(.maskCommand)
        while !callbacks.isEmpty { callbacks.removeFirst()() }
        #expect(delivered == [[.maskShift, .maskSecondaryFn], .maskCommand,
                              [.maskCommand, .maskSecondaryFn], .maskCommand])
    }

    @Test func fnToggleSuppressesNativeKeyToAvoidDuplicateActivation() {
        #expect(VoiceKey.fn.usesToggle)
        #expect(VoiceKey.fn.nativeMappingDestination == 0)
        #expect(VoiceKey.leftControl.nativeMappingDestination == 0)
        #expect(!VoiceKey.rightOption.usesToggle)
        #expect(VoiceKey.rightOption.nativeMappingDestination == VoiceKey.rightOption.hidUsage)
        #expect(VoiceKey.f20.nativeMappingDestination == VoiceKey.f20.hidUsage)
    }
}
