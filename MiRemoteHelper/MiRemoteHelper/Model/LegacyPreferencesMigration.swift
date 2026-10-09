import Foundation

enum LegacyPreferencesMigration {
    static let marker = "legacyPreferencesMigrated.v1"
    private static let keys = [
        "outputUID", "voiceKey", "gainDB", "whisperMode", "whisperGainDB",
        "peripheralIdentifier", "buttonMappingEnabled", "buttonMappings.v1",
        "buttonHoldMappings.v1", "buttonDoubleMappings.v1", "applicationMappings.v1",
        "AppleLanguages", "AppleLocale"
    ]

    static func run(defaults: UserDefaults = .standard,
                    sourceDomain: String = "com.ericyangpan.MiRemoteHelper",
                    destinationDomain: String = "com.yangpan.MiRemoteHelper") {
        var destination = defaults.persistentDomain(forName: destinationDomain) ?? [:]
        guard destination[marker] as? Bool != true else { return }
        let source = defaults.persistentDomain(forName: sourceDomain) ?? [:]
        for key in keys where destination[key] == nil {
            destination[key] = source[key]
        }
        destination[marker] = true
        // Preserve the old domain for rollback and never overwrite newer settings.
        defaults.setPersistentDomain(destination, forName: destinationDomain)
    }
}
