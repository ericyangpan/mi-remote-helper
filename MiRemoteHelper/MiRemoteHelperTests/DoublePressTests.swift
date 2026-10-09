import Foundation
import Testing
@testable import MiRemoteHelper

struct DoublePressTests {
    private let tap = ButtonBinding.preset(.returnKey)
    private let hold = ButtonBinding.shortcut(KeyChord(keyCode: 36, keyLabel: "Return", modifiers: .shift))
    private let double = ButtonBinding.shortcut(KeyChord(keyCode: 36, keyLabel: "Return", modifiers: .command))

    @Test func doublePressNeverSendsAnEarlyReturn() {
        var tracker = ButtonPressTracker()
        _ = tracker.begin(.ok, tap: tap, hold: hold, doubleTap: double, at: 0)
        #expect(tracker.release(.ok, at: 0.05) == nil)
        #expect(tracker.flush(.ok, at: 0.2) == nil)
        _ = tracker.begin(.ok, tap: tap, hold: hold, doubleTap: double, at: 0.2)
        #expect(tracker.release(.ok, at: 0.25) == double)
        #expect(tracker.flush(.ok, at: 1) == nil)
        #expect(tracker.pendingButtons.isEmpty)
    }

    @Test func unassignedDoubleIsImmediateAndAssignedSingleWaits() {
        var tracker = ButtonPressTracker()
        _ = tracker.begin(.left, tap: tap, hold: hold, at: 0)
        #expect(tracker.release(.left, at: 0.1) == tap)
        _ = tracker.begin(.ok, tap: tap, hold: hold, doubleTap: double, at: 1)
        #expect(tracker.release(.ok, at: 1.1) == nil)
        #expect(tracker.flush(.ok, at: 1.39) == nil)
        #expect(tracker.flush(.ok, at: 1.41) == tap)
        #expect(tracker.flush(.ok, at: 2) == nil)
    }

    @Test func longPressOnEitherClickSuppressesSingleAndDouble() throws {
        for second in [false, true] {
            var tracker = ButtonPressTracker()
            if second {
                _ = tracker.begin(.ok, tap: tap, hold: hold, doubleTap: double, at: 0)
                #expect(tracker.release(.ok, at: 0.05) == nil)
            }
            let generation = tracker.begin(.ok, tap: tap, hold: hold, doubleTap: double, at: 0.1)
            let token = try #require(generation)
            #expect(tracker.fire(.ok, generation: token, at: 0.7) == hold)
            #expect(tracker.release(.ok, at: 0.8) == nil)
            #expect(tracker.flush(.ok, at: 1) == nil)
        }
    }

    @Test func tripleClickYieldsDoubleThenSingleAndCancellationDropsPending() {
        var tracker = ButtonPressTracker()
        for index in 0..<3 {
            let time = Double(index) * 0.1
            _ = tracker.begin(.ok, tap: tap, hold: hold, doubleTap: double, at: time)
            #expect(tracker.release(.ok, at: time + 0.04) == (index == 1 ? double : nil))
        }
        #expect(tracker.flush(.ok, at: 0.6) == tap)
        _ = tracker.begin(.ok, tap: tap, hold: hold, doubleTap: double, at: 1)
        _ = tracker.release(.ok, at: 1.1)
        tracker.cancel()
        #expect(tracker.flush(.ok, at: 2) == nil)
    }

    @Test func anotherButtonCanFlushFirstTapBeforeItsOwnAction() {
        var tracker = ButtonPressTracker()
        _ = tracker.begin(.ok, tap: tap, hold: hold, doubleTap: double, at: 0)
        _ = tracker.release(.ok, at: 0.05)
        #expect(tracker.flush(.ok, at: 0.1, force: true) == tap)
        _ = tracker.begin(.left, tap: .preset(.arrowLeft), hold: hold, at: 0.1)
        #expect(tracker.release(.left, at: 0.2) == .preset(.arrowLeft))
        #expect(tracker.flush(.ok, at: 1) == nil)
    }

    @Test func expiredWindowProducesTwoSinglesAndLateHoldDoesNotDouble() {
        var tracker = ButtonPressTracker()
        _ = tracker.begin(.ok, tap: tap, hold: hold, doubleTap: double, at: 0)
        _ = tracker.release(.ok, at: 0.05)
        #expect(tracker.flush(.ok, at: 0.36) == tap)
        _ = tracker.begin(.ok, tap: tap, hold: hold, doubleTap: double, at: 0.36)
        _ = tracker.release(.ok, at: 0.4)
        #expect(tracker.flush(.ok, at: 0.71) == tap)
        _ = tracker.begin(.ok, tap: tap, hold: hold, doubleTap: double, at: 1)
        _ = tracker.release(.ok, at: 1.05)
        _ = tracker.begin(.ok, tap: tap, hold: hold, doubleTap: double, at: 1.2)
        #expect(tracker.release(.ok, at: 1.8) == hold)
        #expect(tracker.flush(.ok, at: 2) == nil)
    }

    @Test @MainActor func doubleMappingsPersistInheritAndRoundTripIndependently() throws {
        let suite = "MiRemoteHelper.DoubleTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = ButtonMappingModel(defaults: defaults)
        let id = MappingDefinition.codex.id
        model.setBinding(double, for: .ok, press: .doubleTap)
        #expect(model.binding(for: .ok, press: .doubleTap, profileID: id) == double)
        model.setBinding(.preset(.disabled), for: .ok, press: .doubleTap, profileID: id)
        let restored = ButtonMappingModel(defaults: defaults)
        #expect(restored.binding(for: .ok, press: .doubleTap) == double)
        #expect(restored.binding(for: .ok, press: .doubleTap, profileID: id).isDisabled)
        #expect(restored.binding(for: .ok) == tap)
        for profile in ["global", id] {
            let definition = try restored.exportDefinition(profileID: profile)
            #expect(definition.version == 2)
            #expect(try MappingDefinitionCodec.decode(MappingDefinitionCodec.encode(definition)) == definition)
        }
        restored.frontmostApplicationChanged(to: "com.openai.codex")
        #expect(restored.runtimeBinding(for: .ok, press: .doubleTap).isDisabled)
        restored.inheritGlobal(.ok, press: .doubleTap, profileID: id)
        #expect(restored.runtimeBinding(for: .ok, press: .doubleTap) == double)
    }

    @Test @MainActor func importsV1WithoutEnablingDoublePressAndRejectsMalformedV2() throws {
        let suite = "MiRemoteHelper.DoubleMigrationTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = ButtonMappingModel(defaults: defaults)
        var object = try #require(JSONSerialization.jsonObject(with: MappingDefinitionCodec.encode(model.globalDefinition)) as? [String: Any])
        object["version"] = 1
        object.removeValue(forKey: "doublePress")
        let migrated = try MappingDefinitionCodec.decode(JSONSerialization.data(withJSONObject: object))
        #expect(migrated.version == 2 && migrated.doublePress.count == 12)
        #expect(migrated.doublePress.values.allSatisfy { $0.isDisabled })
        #expect(migrated.shortPress == model.globalDefinition.shortPress)
        let oldApp: [String: Any] = ["format": "mi-remote-helper.mapping", "version": 1,
            "name": "Codex", "scope": "application", "bundleIdentifier": "com.openai.codex",
            "shortPress": ["ok": ["type": "preset", "action": "returnKey"]], "longPress": [:]]
        let migratedApp = try MappingDefinitionCodec.decode(JSONSerialization.data(withJSONObject: oldApp))
        #expect(migratedApp.doublePress.isEmpty)
        #expect(migratedApp.shortPress["ok"] == tap)
        object["version"] = 2
        #expect(throws: MappingDefinitionError.self) { try MappingDefinitionCodec.decode(JSONSerialization.data(withJSONObject: object)) }
        var invalid = model.globalDefinition
        invalid.doublePress["microphone"] = double
        #expect(throws: MappingDefinitionError.self) { try MappingDefinitionCodec.encode(invalid) }
        invalid = model.globalDefinition
        invalid.doublePress.removeValue(forKey: "ok")
        #expect(throws: MappingDefinitionError.self) { try MappingDefinitionCodec.encode(invalid) }
    }
}
