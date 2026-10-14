import Foundation

/// Portable definitions contain data only. Application entries are sparse overrides.
struct MappingDefinition: Codable, Equatable, Identifiable {
    enum Scope: String, Codable { case global, application }
    var format = "mi-remote-helper.mapping"
    var version = 4
    var name: String
    var scope: Scope
    var bundleIdentifier: String?
    var shortPress: [String: ButtonBinding]
    var longPress: [String: ButtonBinding]
    var doublePress: [String: ButtonBinding] = [:]

    var id: String { scope == .global ? "global" : "application:\(bundleIdentifier ?? "")" }
    static let codex = MappingDefinition(name: "Codex", scope: .application,
        bundleIdentifier: "com.openai.codex", shortPress: ["microphone": .shortcut(KeyChord(keyCode: 34, keyLabel: "I", modifiers: [.command, .option]))], longPress: [:])
    static let grok = MappingDefinition(name: "Grok Bot", scope: .application,
        bundleIdentifier: "com.anysphere.sand", shortPress: ["microphone": .shortcut(KeyChord(keyCode: 34, keyLabel: "I", modifiers: .command))], longPress: [:])
    static func isConfigurable(_ button: RemoteButton, press: ButtonPressKind) -> Bool {
        button != .microphone || press != .hold
    }
    static var shortPressButtons: Set<String> { configurableButtons.union(["microphone"]) }
    static let configurableButtons = Set(RemoteButton.allCases.filter { $0 != .microphone }.map(\.rawValue))

    func override(for button: RemoteButton, press: ButtonPressKind) -> ButtonBinding? {
        switch press {
        case .tap: return shortPress[button.rawValue]
        case .hold: return longPress[button.rawValue]
        case .doubleTap: return doublePress[button.rawValue]
        }
    }

    mutating func set(_ binding: ButtonBinding?, for button: RemoteButton, press: ButtonPressKind) {
        if press == .tap { shortPress[button.rawValue] = binding }
        else if press == .hold { longPress[button.rawValue] = binding }
        else { doublePress[button.rawValue] = binding }
    }

    func validate() throws {
        guard format == "mi-remote-helper.mapping", version == 4 else { throw MappingDefinitionError.unsupportedFormat }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80,
              name.rangeOfCharacter(from: .controlCharacters) == nil else { throw MappingDefinitionError.invalidDefinition }
        if scope == .application {
            guard let bundleIdentifier, Self.validBundleIdentifier(bundleIdentifier) else { throw MappingDefinitionError.invalidDefinition }
        } else {
            guard bundleIdentifier == nil,
                  Set(shortPress.keys) == Self.shortPressButtons,
                  Set(longPress.keys) == Self.configurableButtons,
                  Set(doublePress.keys) == Self.shortPressButtons else { throw MappingDefinitionError.invalidDefinition }
        }
        for (mappings, allowed) in [(shortPress, Self.shortPressButtons), (longPress, Self.configurableButtons), (doublePress, Self.shortPressButtons)] {
            guard Set(mappings.keys).isSubset(of: allowed) else { throw MappingDefinitionError.invalidDefinition }
            for binding in mappings.values {
                switch binding {
                case .preset: break
                case .shortcut(let chord):
                    guard chord.isValid, chord.keyLabel.rangeOfCharacter(from: .controlCharacters) == nil else { throw MappingDefinitionError.invalidDefinition }
                case .dictation: throw MappingDefinitionError.invalidDefinition
                }
            }
        }
    }

    static func validBundleIdentifier(_ value: String) -> Bool {
        value.count <= 255 && value.contains(".") &&
        value.range(of: "^[A-Za-z0-9][A-Za-z0-9.-]*$", options: .regularExpression) != nil
    }
}

struct ApplicationMapping: Codable, Equatable, Identifiable {
    var definition: MappingDefinition
    var enabled = true
    var id: String { definition.id }
}

enum MappingDefinitionError: LocalizedError {
    case unsupportedFormat, invalidDefinition, tooLarge, busy
    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return String.appStatus("This mapping format or version is not supported.")
        case .invalidDefinition: return String.appStatus("The mapping definition is invalid. Check its application, buttons and shortcuts.")
        case .tooLarge: return String.appStatus("Mapping files must be smaller than 256 KB.")
        case .busy: return String.appStatus("Release the remote’s buttons and finish voice input before changing mappings.")
        }
    }
}

enum MappingDefinitionCodec {
    static let maximumBytes = 256 * 1024
    static func decode(_ data: Data) throws -> MappingDefinition {
        guard data.count <= maximumBytes else { throw MappingDefinitionError.tooLarge }
        let definition: MappingDefinition
        do { definition = try JSONDecoder().decode(MappingDefinition.self, from: data) }
        catch { throw MappingDefinitionError.invalidDefinition }
        try definition.validate()
        return definition
    }
    static func encode(_ definition: MappingDefinition) throws -> Data {
        try definition.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(definition)
    }
}

enum MappingResolver {
    static func binding(for button: RemoteButton, press: ButtonPressKind, global: MappingDefinition,
                        applications: [ApplicationMapping], frontmostBundleIdentifier: String?) -> ButtonBinding {
        guard MappingDefinition.isConfigurable(button, press: press) else { return button.defaultBinding(for: press) }
        if let identifier = frontmostBundleIdentifier,
           let application = applications.first(where: { $0.enabled && $0.definition.bundleIdentifier == identifier }),
           let binding = application.definition.override(for: button, press: press) { return binding }
        return global.override(for: button, press: press) ?? button.defaultBinding(for: press)
    }
}

extension MappingDefinition {
    enum CodingKeys: String, CodingKey {
        case format, version, name, scope, bundleIdentifier, shortPress, longPress, doublePress
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        format = try values.decode(String.self, forKey: .format)
        version = try values.decode(Int.self, forKey: .version)
        name = try values.decode(String.self, forKey: .name)
        scope = try values.decode(Scope.self, forKey: .scope)
        bundleIdentifier = try values.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        shortPress = try values.decode([String: ButtonBinding].self, forKey: .shortPress)
        longPress = try values.decode([String: ButtonBinding].self, forKey: .longPress)
        if version == 1 {
            // A v1 file never enables delayed taps. App overrides stay sparse.
            doublePress = scope == .global
                ? Dictionary(uniqueKeysWithValues: Self.configurableButtons.map { ($0, ButtonBinding.preset(.disabled)) }) : [:]
            version = 2
        } else {
            doublePress = try values.decode([String: ButtonBinding].self, forKey: .doublePress)
        }
        if version == 2 {
            guard !shortPress.keys.contains("microphone"), !longPress.keys.contains("microphone"),
                  !doublePress.keys.contains("microphone") else { throw MappingDefinitionError.invalidDefinition }
            if scope == .global { shortPress["microphone"] = .preset(.disabled) }
            version = 3
        }
        if version == 3 {
            guard !doublePress.keys.contains("microphone") else { throw MappingDefinitionError.invalidDefinition }
            if scope == .global { doublePress["microphone"] = .preset(.disabled) }
            version = 4
        }
    }
}
