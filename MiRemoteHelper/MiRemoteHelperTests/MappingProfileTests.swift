import Foundation
import Testing
@testable import MiRemoteHelper

@MainActor
struct MappingProfileTests {
    private func withModel(_ body: (ButtonMappingModel, UserDefaults) throws -> Void) throws {
        let suite = "MiRemoteHelper.ProfileTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(ButtonMappingModel(defaults: defaults), defaults)
    }

    @Test func resolvesExactAppOverridesAndFallsBackPerGesture() throws {
        try withModel { model, _ in
            let id = MappingDefinition.codex.id
            model.setBinding(.preset(.deleteBackward), for: .back)
            model.setBinding(.preset(.disabled), for: .back, profileID: id)
            model.setBinding(.preset(.playPause), for: .tv, press: .hold, profileID: id)
            model.frontmostApplicationChanged(to: "com.openai.codex")
            #expect(model.runtimeBinding(for: .back, press: .tap) == .preset(.disabled))
            #expect(model.runtimeBinding(for: .tv, press: .hold) == .preset(.playPause))
            #expect(model.runtimeBinding(for: .up, press: .hold) == .preset(.pageUp))
            #expect(model.runtimeBinding(for: .microphone, press: .hold) == .dictation)
            for app in [nil, "com.openai.chat", "com.openai.codex.other"] {
                model.frontmostApplicationChanged(to: app)
                #expect(model.runtimeBinding(for: .back, press: .tap) == .preset(.deleteBackward))
                #expect(model.runtimeBinding(for: .tv, press: .hold) == .preset(.volumeMute))
            }
            model.frontmostApplicationChanged(to: "com.openai.codex")
            model.setApplicationEnabled(false, profileID: id)
            #expect(model.runtimeBinding(for: .back, press: .tap) == .preset(.deleteBackward))
        }
    }

    @Test func inheritanceTracksGlobalChangesAndPersistsOverrides() throws {
        try withModel { model, defaults in
            let id = MappingDefinition.codex.id
            #expect(model.inheritsGlobal(.menu, press: .tap, profileID: id))
            model.setBinding(.preset(.escape), for: .menu)
            #expect(model.binding(for: .menu, profileID: id) == .preset(.escape))
            model.setBinding(.preset(.returnKey), for: .menu, profileID: id)
            model.setBinding(.preset(.disabled), for: .menu)
            #expect(model.binding(for: .menu, profileID: id) == .preset(.returnKey))
            let restored = ButtonMappingModel(defaults: defaults)
            #expect(restored.binding(for: .menu, profileID: id) == .preset(.returnKey))
            restored.inheritGlobal(.menu, press: .tap, profileID: id)
            #expect(restored.binding(for: .menu, profileID: id) == .preset(.disabled))
            #expect(restored.inheritsGlobal(.menu, press: .tap, profileID: id))
        }
    }

    @Test func globalAndAppExportsRoundTripWithoutMixingScopes() throws {
        try withModel { model, _ in
            let id = MappingDefinition.codex.id
            let chord = ButtonBinding.shortcut(KeyChord(keyCode: 8, keyLabel: "C", modifiers: [.command]))
            model.setBinding(chord, for: .tv, press: .hold, profileID: id)
            for profileID in ["global", id] {
                let definition = try model.exportDefinition(profileID: profileID)
                #expect(try MappingDefinitionCodec.decode(MappingDefinitionCodec.encode(definition)) == definition)
            }
            let global = try model.exportDefinition(profileID: "global")
            let app = try model.exportDefinition(profileID: id)
            #expect(global.shortPress.count == 12 && global.longPress.count == 12)
            #expect(app.shortPress.isEmpty && app.longPress.count == 1)
            model.reset(profileID: id)
            #expect(model.binding(for: .tv, press: .hold, profileID: id) == .preset(.volumeMute))
            try model.importDefinition(app)
            #expect(model.binding(for: .tv, press: .hold, profileID: id) == chord)
            model.setBinding(.preset(.disabled), for: .tv)
            try model.importDefinition(global)
            #expect(model.binding(for: .tv) == .preset(.playPause))
            #expect(model.binding(for: .tv, press: .hold, profileID: id) == chord)
        }
    }

    @Test func invalidImportsLeaveAllMappingsUnchanged() throws {
        try withModel { model, _ in
            let before = model.globalDefinition
            let applications = model.applicationProfiles
            var invalid = MappingDefinition.codex
            invalid.shortPress["microphone"] = .preset(.disabled)
            #expect(throws: MappingDefinitionError.self) { try model.importDefinition(invalid) }
            invalid = .codex
            invalid.longPress["tv"] = .shortcut(KeyChord(keyCode: 999, keyLabel: "x", modifiers: []))
            #expect(throws: MappingDefinitionError.self) { try model.importDefinition(invalid) }
            invalid = .codex
            invalid.bundleIdentifier = "../../Codex"
            #expect(throws: MappingDefinitionError.self) { try model.importDefinition(invalid) }
            invalid = before
            invalid.shortPress.removeValue(forKey: "up")
            #expect(throws: MappingDefinitionError.self) { try model.importDefinition(invalid) }
            #expect(model.globalDefinition == before)
            #expect(model.applicationProfiles == applications)
            model.canEdit = { false }
            #expect(throws: MappingDefinitionError.self) { try model.importDefinition(before) }
        }
    }

    @Test func shortcutSaveReportsRejectedEditsAndPreservesThePreviousBinding() throws {
        try withModel { model, defaults in
            let original = model.binding(for: .ok)
            let custom = ButtonBinding.shortcut(KeyChord(keyCode: 36, keyLabel: "Return", modifiers: [.command]))
            model.canEdit = { false }
            #expect(!model.setBinding(custom, for: .ok))
            #expect(model.binding(for: .ok) == original)
            model.canEdit = { true }
            #expect(!model.setBinding(custom, for: .ok, profileID: "missing-app"))
            #expect(!model.setBinding(custom, for: .microphone))
            #expect(model.setBinding(custom, for: .ok))
            #expect(ButtonMappingModel(defaults: defaults).binding(for: .ok) == custom)
        }
    }

    @Test func rejectsUnknownFormatsVersionsOversizedFilesAndInvalidActions() throws {
        var definition = MappingDefinition.codex
        definition.version = 999
        #expect(throws: MappingDefinitionError.self) { try MappingDefinitionCodec.decode(JSONEncoder().encode(definition)) }
        definition = .codex
        definition.format = "another-format"
        #expect(throws: MappingDefinitionError.self) { try MappingDefinitionCodec.decode(JSONEncoder().encode(definition)) }
        #expect(throws: MappingDefinitionError.self) { try MappingDefinitionCodec.decode(Data(repeating: 32, count: MappingDefinitionCodec.maximumBytes + 1)) }
        definition = .codex
        definition.shortPress["tv"] = .dictation
        #expect(throws: MappingDefinitionError.self) { try MappingDefinitionCodec.encode(definition) }
        definition = .codex
        definition.longPress["unknown-button"] = .preset(.escape)
        #expect(throws: MappingDefinitionError.self) { try MappingDefinitionCodec.encode(definition) }
    }

    @Test func appManagementDeduplicatesAndKeepsDeletedExtensionsDeleted() throws {
        try withModel { model, defaults in
            let id = MappingDefinition.codex.id
            try model.addApplication(name: "Another display name", bundleIdentifier: "com.openai.codex")
            #expect(model.applicationProfiles.count == 1)
            model.setApplicationEnabled(false, profileID: id)
            try model.importDefinition(.codex)
            #expect(model.selectedApplication?.enabled == false)
            model.removeApplication(id)
            #expect(model.selectedProfileID == "global")
            #expect(ButtonMappingModel(defaults: defaults).applicationProfiles.isEmpty)
            try model.addApplication(name: "Editor", bundleIdentifier: "com.example.editor")
            #expect(model.applicationProfiles.count == 1)
        }
    }

    @Test func builtInDefinitionsAreValidAndCodexStartsWithInheritance() throws {
        try withModel { model, _ in
            let codex = try #require(model.applicationProfiles.first?.definition)
            #expect(codex == .codex)
            #expect(codex.shortPress.isEmpty && codex.longPress.isEmpty)
            for definition in [codex, model.globalDefinition] {
                #expect(try MappingDefinitionCodec.decode(MappingDefinitionCodec.encode(definition)) == definition)
            }
            #expect(model.globalDefinition.shortPress.count == 12)
            #expect(model.globalDefinition.longPress.count == 12)
        }
    }
}
