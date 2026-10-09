import Foundation
import CoreGraphics
import Testing
@testable import MiRemoteHelper

struct ButtonMappingTests {
    @Test func unchangedMappingDoesNotRequireWritableService() {
        let current = [KeyMapping(source: 99, destination: 100), KeyMapping(source: KeyMapping.microphone, destination: 0)]
        var writes = 0
        #expect(KeyMapping.update(current: current, desired: current.reversed(), write: { _ in
            writes += 1
            return false
        }, read: { current }))
        #expect(writes == 0)
    }

    @Test func mappingWriteUsesVerifiedStateAndRejectsUnappliedChanges() {
        let current = [KeyMapping(source: 99, destination: 100)]
        let desired = KeyMapping.applying([KeyMapping.microphone: 0], to: current)
        var stored = current
        #expect(KeyMapping.update(current: current, desired: desired, write: {
            stored = $0.reversed()
            return false
        }, read: { stored }))
        #expect(!KeyMapping.update(current: current, desired: desired, write: { _ in true }, read: { current }))
    }

    @Test func clearTextSelectsAllThenDeletesWithoutCommandModifier() throws {
        let events = try #require(KeyboardInjector.clearTextEvents())
        #expect(events.map(\.type) == [.keyDown, .keyUp, .keyDown, .keyUp])
        #expect(events.map { $0.getIntegerValueField(.keyboardEventKeycode) } == [0, 0, 51, 51])
        #expect(events.map(\.flags) == [.maskCommand, .maskCommand, [], []])
        #expect(events.allSatisfy { $0.getIntegerValueField(.eventSourceUserData) == KeyboardInjector.syntheticEventMarker })
        #expect(RemoteButton.back.defaultHoldBinding == .preset(.clearText))
        let binding = ButtonBinding.preset(.clearText)
        #expect(try JSONDecoder().decode(ButtonBinding.self, from: JSONEncoder().encode(binding)) == binding)
    }

    @Test func allPhysicalButtonsHaveUniqueUsagesAndDefaults() {
        #expect(RemoteButton.allCases.count == 13)
        #expect(Set(RemoteButton.allCases.map(\.hidUsage)).count == 13)
        #expect(RemoteButton.microphone.defaultBinding == .dictation)
        #expect(RemoteButton.power.defaultBinding == .preset(.disabled))
        #expect(RemoteButton.tv.defaultBinding == .preset(.playPause))
        #expect(RemoteButton.home.hidUsage == 0x4A)
        #expect(RemoteButton.menu.hidUsage == 0x65)
    }

    @Test func deviceLocalSuppressionRestoresOwnedKeysAndPreservesExternalEdits() {
        let voice = KeyMapping(source: KeyMapping.microphone, destination: VoiceKey.fn.hidUsage)
        let unrelated = KeyMapping(source: 99, destination: 100)
        let oldUp = KeyMapping(source: 0x700000052, destination: 123)
        let suppressed: [UInt64: UInt64] = [0x700000052: 0, 0x70000004F: 0]
        let applied = KeyMapping.applying(suppressed, to: [voice, unrelated, oldUp])
        #expect(applied.contains(voice))
        #expect(applied.contains(unrelated))
        #expect(applied.filter { suppressed[$0.source] != nil }.allSatisfy { $0.destination == 0 })
        let restored = KeyMapping.restoring(applied, originals: [oldUp.source: oldUp.destination], installed: suppressed)
        #expect(Set(restored.map(\.source)) == [voice.source, unrelated.source, oldUp.source])
        #expect(restored.contains(oldUp))
        let external = KeyMapping(source: oldUp.source, destination: 456)
        let changed = KeyMapping.applying([external.source: external.destination], to: applied)
        let preserved = KeyMapping.restoring(changed, originals: [oldUp.source: oldUp.destination], installed: suppressed)
        #expect(preserved.contains(external))
        #expect(!preserved.contains { $0.source == 0x70000004F })
    }

    @Test func parsesRawLittleEndianReportsAndRejectsMalformedInput() {
        let data = Data([0xF1, 0, 0x3E, 0, 0, 0])
        #expect(RemoteHIDReportParser.usages(reportID: 1, data: data) == [0xF1, 0x3E])
        #expect(RemoteHIDReportParser.usages(reportID: 1, data: Data([1]) + data) == [0xF1, 0x3E])
        #expect(RemoteHIDReportParser.usages(reportID: 1, data: Data(repeating: 0, count: 6)) == [])
        for malformed in [Data(), Data([0x3E]), Data([0x3E, 0]), Data(repeating: 0, count: 7)] {
            #expect(RemoteHIDReportParser.usages(reportID: 1, data: malformed) == nil)
        }
        #expect(RemoteHIDReportParser.usages(reportID: 2, data: data) == nil)
    }

    @Test func deduplicatesPressesAndSeparatesOverlappingReleases() {
        var edges = RemoteButtonEdges()
        #expect(edges.update([0x52]).down == [0x52])
        #expect(edges.update([0x52]).down.isEmpty)
        let overlap = edges.update([0x52, 0x28])
        #expect(overlap.down == [0x28])
        #expect(overlap.up.isEmpty)
        #expect(edges.update([0x28]).up == [0x52])
        edges.reset()
        #expect(edges.update([]).up.isEmpty)
        #expect(edges.update([0x52]).down == [0x52])
    }

    @Test @MainActor func persistsMappingsAndRestoresDefaults() throws {
        let suite = "MiRemoteHelper.MappingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = ButtonMappingModel(defaults: defaults)
        #expect(!model.enabled)
        let chord = KeyChord(keyCode: 8, keyLabel: "C", modifiers: [.command, .shift])
        model.setBinding(.shortcut(chord), for: .tv)
        model.setBinding(.preset(.playPause), for: .microphone)
        var voiceRefreshes = 0
        model.onAvailabilityChange = { voiceRefreshes += 1 }
        model.setEnabled(true)
        #expect(voiceRefreshes == 1)
        #expect(model.binding(for: .microphone) == .dictation)
        let restored = ButtonMappingModel(defaults: defaults)
        #expect(restored.enabled)
        #expect(restored.binding(for: .tv) == .shortcut(chord))
        #expect(restored.binding(for: .microphone) == .dictation)
        #expect(chord.displayName == "⇧⌘C")
        restored.reset()
        #expect(restored.binding(for: .microphone) == .dictation)
        #expect(restored.binding(for: .tv) == .preset(.playPause))
        #expect(ButtonMappingModel(defaults: defaults).binding(for: .tv) == .preset(.playPause))
    }

    @Test @MainActor func rejectsInvalidMappingsAndEditsDuringVoiceSession() throws {
        let suite = "MiRemoteHelper.MappingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let bad = KeyChord(keyCode: 999, keyLabel: "bad", modifiers: [])
        defaults.set(try JSONEncoder().encode(["tv": ButtonBinding.shortcut(bad), "home": .dictation]), forKey: "buttonMappings.v1")
        let model = ButtonMappingModel(defaults: defaults)
        #expect(model.binding(for: .tv) == .preset(.playPause))
        #expect(model.binding(for: .home) == .preset(.appSwitcher))
        model.setBinding(.dictation, for: .tv)
        #expect(model.binding(for: .tv) == .preset(.playPause))
        model.canEdit = { false }
        model.setBinding(.preset(.volumeMute), for: .tv)
        model.setEnabled(true)
        #expect(model.binding(for: .tv) == .preset(.playPause))
        #expect(!model.enabled)
        #expect(!KeyChord(keyCode: 8, keyLabel: "C", modifiers: .init(rawValue: 128)).isValid)
    }
    @Test @MainActor func migratesVoiceOverridesAndRejectsNewOnes() throws {
        let suite = "MiRemoteHelper.MappingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode(["microphone": ButtonBinding.preset(.disabled), "tv": .preset(.playPause)]), forKey: "buttonMappings.v1")
        let model = ButtonMappingModel(defaults: defaults)
        #expect(model.binding(for: .microphone) == .dictation)
        #expect(model.binding(for: .tv) == .preset(.playPause))
        for binding in [ButtonBinding.preset(.disabled), .shortcut(KeyChord(keyCode: 8, keyLabel: "C", modifiers: [.command]))] {
            model.setBinding(binding, for: .microphone)
            #expect(model.binding(for: .microphone) == .dictation)
        }
        let saved = try JSONDecoder().decode([String: ButtonBinding].self, from: #require(defaults.data(forKey: "buttonMappings.v1")))
        #expect(saved["microphone"] == nil)
    }

    @Test func directionalTapsAndHoldsDoNotOverlap() throws {
        var tracker = ButtonPressTracker()
        let leftValue = tracker.begin(.left, tap: .preset(.arrowLeft), hold: RemoteButton.left.defaultHoldBinding, at: 0)
        let left = try #require(leftValue)
        #expect(tracker.fire(.left, generation: left, at: 0.49) == nil)
        #expect(tracker.release(.left, at: 0.49) == .preset(.arrowLeft))
        #expect(tracker.fire(.left, generation: left, at: 1) == nil)
        let heldValue = tracker.begin(.left, tap: .preset(.arrowLeft), hold: RemoteButton.left.defaultHoldBinding, at: 2)
        let held = try #require(heldValue)
        #expect(tracker.fire(.left, generation: held, at: 2.5) == .preset(.homeKey))
        #expect(tracker.fire(.left, generation: held, at: 3) == nil)
        #expect(tracker.release(.left, at: 4) == nil)
        _ = tracker.begin(.right, tap: .preset(.arrowRight), hold: RemoteButton.right.defaultHoldBinding, at: 5)
        // A delayed timer must not turn a long press into a tap.
        #expect(tracker.release(.right, at: 5.5) == .preset(.endKey))
        #expect(tracker.release(.right, at: 6) == nil)
    }

    @Test func directionalCancellationRejectsStaleTimersAndPreservesCustomTaps() throws {
        var tracker = ButtonPressTracker()
        let custom = ButtonBinding.shortcut(KeyChord(keyCode: 8, keyLabel: "C", modifiers: [.command]))
        let oldValue = tracker.begin(.right, tap: custom, hold: RemoteButton.right.defaultHoldBinding, at: 0)
        let old = try #require(oldValue)
        #expect(tracker.begin(.right, tap: custom, hold: RemoteButton.right.defaultHoldBinding, at: 0.1) == nil)
        tracker.cancel()
        #expect(tracker.release(.right, at: 1) == nil)
        let currentValue = tracker.begin(.right, tap: custom, hold: RemoteButton.right.defaultHoldBinding, at: 2)
        let current = try #require(currentValue)
        #expect(current != old)
        #expect(tracker.fire(.right, generation: old, at: 3) == nil)
        #expect(tracker.release(.right, at: 2.1) == custom)
        #expect(tracker.begin(.microphone, tap: .dictation, hold: RemoteButton.microphone.defaultHoldBinding, at: 0) == nil)
        let lValue = tracker.begin(.left, tap: .preset(.arrowLeft), hold: RemoteButton.left.defaultHoldBinding, at: 10)
        let l = try #require(lValue)
        let rValue = tracker.begin(.right, tap: .preset(.arrowRight), hold: RemoteButton.right.defaultHoldBinding, at: 10)
        let r = try #require(rValue)
        #expect(tracker.fire(.left, generation: l, at: 10.5) == .preset(.homeKey))
        #expect(tracker.fire(.right, generation: r, at: 10.5) == .preset(.endKey))
    }

    @Test @MainActor func savesIndependentShortAndLongMappingsAndRestoresBoth() throws {
        let suite = "MiRemoteHelper.MappingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // Existing short-press choices must survive adding long-press settings.
        defaults.set(try JSONEncoder().encode(["back": ButtonBinding.preset(.deleteBackward)]), forKey: "buttonMappings.v1")
        let model = ButtonMappingModel(defaults: defaults)
        let shortcut = ButtonBinding.shortcut(KeyChord(keyCode: 8, keyLabel: "C", modifiers: [.command]))
        #expect(model.binding(for: .left, press: .hold) == .preset(.homeKey))
        #expect(model.binding(for: .right, press: .hold) == .preset(.endKey))
        #expect(model.binding(for: .back, press: .hold) == .preset(.clearText))
        #expect(model.binding(for: .up, press: .hold) == .preset(.pageUp))
        #expect(model.binding(for: .down, press: .hold) == .preset(.pageDown))
        model.setBinding(shortcut, for: .back, press: .hold)
        model.setBinding(.preset(.disabled), for: .up, press: .hold)
        model.setBinding(.preset(.pageDown), for: .tv, press: .hold)
        model.setBinding(.preset(.disabled), for: .left, press: .hold)
        let restored = ButtonMappingModel(defaults: defaults)
        #expect(restored.binding(for: .back) == .preset(.deleteBackward))
        #expect(restored.binding(for: .up, press: .hold) == .preset(.disabled))
        #expect(restored.binding(for: .down, press: .hold) == .preset(.pageDown))
        #expect(restored.binding(for: .tv, press: .hold) == .preset(.pageDown))
        #expect(restored.binding(for: .back, press: .hold) == shortcut)
        #expect(restored.binding(for: .left, press: .hold) == .preset(.disabled))
        restored.reset()
        let reset = ButtonMappingModel(defaults: defaults)
        #expect(reset.binding(for: .back) == .preset(.escape))
        #expect(reset.binding(for: .back, press: .hold) == .preset(.clearText))
        #expect(reset.binding(for: .left, press: .hold) == .preset(.homeKey))
        #expect(reset.binding(for: .up, press: .hold) == .preset(.pageUp))
        #expect(reset.binding(for: .down, press: .hold) == .preset(.pageDown))
    }

    @Test @MainActor func rejectsInvalidAndVoiceLongMappingsAndBusyEdits() throws {
        let suite = "MiRemoteHelper.MappingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let bad = KeyChord(keyCode: 999, keyLabel: "bad", modifiers: [])
        defaults.set(try JSONEncoder().encode(["microphone": ButtonBinding.preset(.disabled), "tv": .shortcut(bad), "home": .dictation]), forKey: "buttonHoldMappings.v1")
        let model = ButtonMappingModel(defaults: defaults)
        #expect(model.binding(for: .microphone, press: .hold) == .dictation)
        #expect(model.binding(for: .home, press: .hold) == .preset(.disabled))
        #expect(model.binding(for: .tv, press: .hold) == .preset(.volumeMute))
        model.setBinding(.preset(.playPause), for: .microphone, press: .hold)
        model.setBinding(.dictation, for: .tv, press: .hold)
        model.setBinding(.shortcut(bad), for: .tv, press: .hold)
        #expect(model.holdBindings.isEmpty)
        model.canEdit = { false }
        model.setBinding(.preset(.playPause), for: .tv, press: .hold)
        #expect(model.holdBindings.isEmpty)
    }

    @Test func everyNonVoiceButtonUsesItsConfiguredHoldExactlyOnce() throws {
        for button in RemoteButton.allCases where button != .microphone {
            var tracker = ButtonPressTracker()
            let hold = ButtonBinding.shortcut(KeyChord(keyCode: 8, keyLabel: "C", modifiers: [.command]))
            let token = tracker.begin(button, tap: button.defaultBinding, hold: hold, at: 0)
            let generation = try #require(token)
            #expect(tracker.fire(button, generation: generation, at: 0.5) == hold)
            #expect(tracker.fire(button, generation: generation, at: 1) == nil)
            #expect(tracker.release(button, at: 2) == nil)
            _ = tracker.begin(button, tap: button.defaultBinding, hold: .preset(.disabled), at: 3)
            #expect(tracker.release(button, at: 4) == .preset(.disabled))
            _ = tracker.begin(button, tap: button.defaultBinding, hold: hold, at: 5)
            #expect(tracker.release(button, at: 5.1) == button.defaultBinding)
        }
    }

}
