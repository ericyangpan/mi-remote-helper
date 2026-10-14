import Foundation

enum RemoteButton: String, CaseIterable, Codable, Identifiable {
    case microphone
    case power
    case up
    case down
    case ok
    case left
    case right
    case back
    case home
    case volumeUp = "volume_up"
    case volumeDown = "volume_down"
    case menu
    case tv

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .microphone: return "mic"
        case .power: return "power"
        case .up: return "arrow.up"
        case .left: return "arrow.left"
        case .ok: return "checkmark.circle"
        case .right: return "arrow.right"
        case .down: return "arrow.down"
        case .back: return "chevron.left"
        case .volumeUp: return "plus"
        case .home: return "house"
        case .volumeDown: return "minus"
        case .menu: return "line.3.horizontal"
        case .tv: return "tv"
        }
    }

    var hidUsage: UInt16 {
        switch self {
        case .microphone: return 0x3E
        case .power: return 0x66
        case .up: return 0x52
        case .left: return 0x50
        case .ok: return 0x28
        case .right: return 0x4F
        case .down: return 0x51
        case .back: return 0xF1
        case .volumeUp: return 0x80
        case .home: return 0x4A
        case .volumeDown: return 0x81
        case .menu: return 0x65
        case .tv: return 0x35
        }
    }

    var displayName: String {
        switch self {
        case .microphone: return String.appLocalized("Voice")
        case .power: return String.appLocalized("Power")
        case .up: return String.appLocalized("Up")
        case .left: return String.appLocalized("Left")
        case .ok: return String.appLocalized("OK")
        case .right: return String.appLocalized("Right")
        case .down: return String.appLocalized("Down")
        case .back: return String.appLocalized("Back")
        case .volumeUp: return String.appLocalized("Volume Up")
        case .home: return String.appLocalized("Home")
        case .volumeDown: return String.appLocalized("Volume Down")
        case .menu: return String.appLocalized("Menu")
        case .tv: return String.appLocalized("TV")
        }
    }

    static let usageMap = Dictionary(
        uniqueKeysWithValues: allCases.map { ($0.hidUsage, $0) }
    )

}

enum ButtonAction: String, CaseIterable, Codable, Identifiable {
    case disabled
    case escape
    case returnKey
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
    case homeKey
    case endKey
    case pageUp
    case pageDown
    case deleteBackward
    case clearText
    case showDesktop
    case contextMenu
    case appSwitcher
    case mouseRightClick
    case volumeUp
    case volumeDown
    case volumeMute
    case playPause

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .disabled: return "minus.circle"
        case .escape: return "escape"
        case .returnKey: return "return"
        case .arrowUp: return "arrow.up"
        case .arrowDown: return "arrow.down"
        case .arrowLeft: return "arrow.left"
        case .arrowRight: return "arrow.right"
        case .homeKey: return "arrow.up.left"
        case .endKey: return "arrow.down.right"
        case .pageUp: return "arrow.up.square"
        case .pageDown: return "arrow.down.square"
        case .deleteBackward: return "delete.left"
        case .clearText: return "eraser"
        case .showDesktop: return "display"
        case .contextMenu: return "text.bubble"
        case .appSwitcher: return "rectangle.on.rectangle"
        case .mouseRightClick: return "computermouse"
        case .volumeUp: return "speaker.plus"
        case .volumeDown: return "speaker.minus"
        case .volumeMute: return "speaker.slash"
        case .playPause: return "playpause"
        }
    }

    /// Standard keyboard labels stay recognizable beside localized actions.
    var keyLabel: String? {
        switch self {
        case .escape: return "Esc"
        case .returnKey: return "Return"
        case .homeKey: return "Home"
        case .endKey: return "End"
        case .pageUp: return "Page Up"
        case .pageDown: return "Page Down"
        case .deleteBackward: return "Delete"
        default: return nil
        }
    }

    private var searchAliases: [String] {
        switch self {
        case .escape: return ["Esc", "Escape"]
        case .returnKey: return ["Return", "Enter"]
        case .homeKey: return ["Home"]
        case .endKey: return ["End"]
        case .pageUp: return ["Page Up", "PageUp", "PgUp"]
        case .pageDown: return ["Page Down", "PageDown", "PgDown", "PgDn"]
        case .deleteBackward: return ["Delete", "Backspace"]
        case .arrowUp: return ["Arrow Up"]
        case .arrowDown: return ["Arrow Down"]
        case .arrowLeft: return ["Arrow Left"]
        case .arrowRight: return ["Arrow Right"]
        default: return []
        }
    }

    func matchesSearch(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || displayName.localizedStandardContains(query)
            || searchAliases.contains { $0.localizedStandardContains(query) }
    }

    var displayName: String {
        switch self {
        case .disabled: return String.appLocalized("No Action")
        case .escape: return String.appLocalized("Escape")
        case .returnKey: return String.appLocalized("Return")
        case .arrowUp: return String.appLocalized("Arrow Up")
        case .arrowDown: return String.appLocalized("Arrow Down")
        case .arrowLeft: return String.appLocalized("Arrow Left")
        case .arrowRight: return String.appLocalized("Arrow Right")
        case .homeKey: return String.appLocalized("Keyboard Home")
        case .endKey: return String.appLocalized("Keyboard End")
        case .pageUp: return String.appLocalized("Page Up")
        case .pageDown: return String.appLocalized("Page Down")
        case .deleteBackward: return String.appLocalized("Delete (Backspace)")
        case .clearText: return String.appLocalized("Clear All Text")
        case .showDesktop: return String.appLocalized("Show Desktop")
        case .contextMenu: return String.appLocalized("Context Menu (Right Click)")
        case .appSwitcher: return String.appLocalized("Switch App")
        case .mouseRightClick: return String.appLocalized("Right Click")
        case .volumeUp: return String.appLocalized("Volume Up")
        case .volumeDown: return String.appLocalized("Volume Down")
        case .volumeMute: return String.appLocalized("Mute")
        case .playPause: return String.appLocalized("Play / Pause")
        }
    }
}

struct KeyChord: Codable, Equatable, Hashable {
    struct Modifiers: OptionSet, Codable, Hashable {
        let rawValue: UInt8

        static let command = Self(rawValue: 1 << 0)
        static let control = Self(rawValue: 1 << 1)
        static let option = Self(rawValue: 1 << 2)
        static let shift = Self(rawValue: 1 << 3)
    }

    let keyCode: UInt16
    let keyLabel: String
    let modifiers: Modifiers

    var isValid: Bool {
        keyCode <= 127 && modifiers.rawValue & ~15 == 0 && !keyLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && keyLabel.count <= 24
    }

    var displayName: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(keyLabel)
        return parts.joined()
    }
}

enum ButtonBinding: Codable, Equatable {
    case preset(ButtonAction)
    case shortcut(KeyChord)
    case dictation

    private enum CodingKeys: String, CodingKey { case type, action, chord }
    private enum Kind: String, Codable { case preset, shortcut, dictation }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .preset:
            self = .preset(try container.decode(ButtonAction.self, forKey: .action))
        case .shortcut:
            self = .shortcut(try container.decode(KeyChord.self, forKey: .chord))
        case .dictation:
            self = .dictation
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .preset(action):
            try container.encode(Kind.preset, forKey: .type)
            try container.encode(action, forKey: .action)
        case let .shortcut(chord):
            try container.encode(Kind.shortcut, forKey: .type)
            try container.encode(chord, forKey: .chord)
        case .dictation:
            try container.encode(Kind.dictation, forKey: .type)
        }
    }

    var displayName: String {
        switch self {
        case let .preset(action): return action.displayName
        case let .shortcut(chord): return chord.displayName
        case .dictation: return String.appLocalized("Voice Input")
        }
    }

    var isDisabled: Bool {
        if case .preset(.disabled) = self { return true }
        return false
    }
}

extension RemoteButton {
    var defaultDoubleBinding: ButtonBinding {
        self == .ok
            ? .shortcut(KeyChord(keyCode: 36, keyLabel: "Return", modifiers: .command))
            : .preset(.disabled)
    }

    func defaultBinding(for press: ButtonPressKind) -> ButtonBinding {
        switch press {
        case .tap: return defaultBinding
        case .doubleTap: return defaultDoubleBinding
        case .hold: return defaultHoldBinding
        }
    }

    var defaultHoldBinding: ButtonBinding {
        switch self {
        case .microphone: return .dictation
        case .ok: return .shortcut(KeyChord(keyCode: 36, keyLabel: "Return", modifiers: .shift))
        case .left: return .preset(.homeKey)
        case .right: return .preset(.endKey)
        case .up: return .preset(.pageUp)
        case .down: return .preset(.pageDown)
        case .back: return .preset(.clearText)
        case .tv: return .preset(.volumeMute)
        default: return .preset(.disabled)
        }
    }

    var defaultBinding: ButtonBinding {
        switch self {
        case .microphone: return .preset(.disabled)
        case .power: return .preset(.disabled)
        case .tv: return .preset(.playPause)
        case .up: return .preset(.arrowUp)
        case .down: return .preset(.arrowDown)
        case .left: return .preset(.arrowLeft)
        case .right: return .preset(.arrowRight)
        case .ok: return .preset(.returnKey)
        case .back: return .preset(.escape)
        case .home: return .preset(.appSwitcher)
        case .menu: return .preset(.contextMenu)
        case .volumeUp: return .preset(.volumeUp)
        case .volumeDown: return .preset(.volumeDown)
        }
    }
}

struct RemoteButtonEdges {
    private(set) var held = Set<UInt16>()
    mutating func update(_ usages: Set<UInt16>) -> (down: Set<UInt16>, up: Set<UInt16>) {
        let result = (usages.subtracting(held), held.subtracting(usages))
        held = usages
        return result
    }
    mutating func reset() { held.removeAll() }
}

enum RemoteHIDReportParser {
    static func usages(reportID: UInt32, data: Data) -> Set<UInt16>? {
        guard reportID == 1 else { return nil }
        var bytes = Array(data)
        if bytes.count == 7, bytes.first == UInt8(reportID) {
            bytes.removeFirst()
        }
        guard bytes.count == 6 else { return nil }

        var result = Set<UInt16>()
        for index in stride(from: 0, to: bytes.count, by: 2) {
            let usage = UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8
            if usage != 0 { result.insert(usage) }
        }
        return result
    }
}

enum ButtonPressKind: String, CaseIterable, Identifiable {
    case tap, doubleTap, hold
    var id: Self { self }
    var title: String {
        switch self {
        case .tap: return String.appLocalized("Short Press")
        case .doubleTap: return String.appLocalized("Double Press")
        case .hold: return String.appLocalized("Long Press")
        }
    }
}
