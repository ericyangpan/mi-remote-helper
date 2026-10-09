import Foundation
import Testing
@testable import MiRemoteHelper

struct LegacyPreferencesMigrationTests {
    @Test func preservesMappingsAndExistingSettingsAndMigratesOnlyOnce() throws {
        let source = "MigrationSource.\(UUID().uuidString)"
        let target = "MigrationTarget.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: target))
        defer {
            defaults.removePersistentDomain(forName: source)
            defaults.removePersistentDomain(forName: target)
        }
        let mappings = Data("saved-mappings".utf8)
        defaults.setPersistentDomain([
            "gainDB": 3.0, "whisperMode": true, "voiceKey": "fn",
            "applicationMappings.v1": mappings, "buttonDoubleMappings.v1": mappings,
            "AppleLanguages": ["zh-Hans"], "unrelated": true
        ], forName: source)
        defaults.set(9.0, forKey: "gainDB")
        LegacyPreferencesMigration.run(defaults: defaults, sourceDomain: source, destinationDomain: target)
        #expect(defaults.double(forKey: "gainDB") == 9)
        #expect(defaults.bool(forKey: "whisperMode"))
        #expect(defaults.string(forKey: "voiceKey") == "fn")
        #expect(defaults.data(forKey: "applicationMappings.v1") == mappings)
        #expect(defaults.data(forKey: "buttonDoubleMappings.v1") == mappings)
        #expect(defaults.stringArray(forKey: "AppleLanguages") == ["zh-Hans"])
        #expect(defaults.object(forKey: "unrelated") == nil)
        #expect(defaults.persistentDomain(forName: source)?["voiceKey"] as? String == "fn")
        defaults.removeObject(forKey: "voiceKey")
        LegacyPreferencesMigration.run(defaults: defaults, sourceDomain: source, destinationDomain: target)
        #expect(defaults.object(forKey: "voiceKey") == nil)
    }
}
