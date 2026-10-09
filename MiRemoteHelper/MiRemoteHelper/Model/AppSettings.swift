import Foundation
import Combine
import OSLog

final class AppSettings: ObservableObject {
    private let defaults: UserDefaults
    @Published var outputUID: String { didSet { defaults.set(outputUID, forKey: "outputUID") } }
    @Published var keepSystemInput: Bool { didSet { defaults.set(keepSystemInput, forKey: "keepSystemInput") } }
    @Published var voiceKey: VoiceKey { didSet { defaults.set(voiceKey.rawValue, forKey: "voiceKey") } }
    @Published var gainDB: Double { didSet { defaults.set(gainDB, forKey: "gainDB") } }
    @Published var whisperMode: Bool { didSet { defaults.set(whisperMode, forKey: "whisperMode") } }
    @Published var whisperGainDB: Double { didSet { defaults.set(whisperGainDB, forKey: "whisperGainDB") } }
    var activeGainDB: Double {
        get { whisperMode ? whisperGainDB : gainDB }
        set { if whisperMode { whisperGainDB = newValue } else { gainDB = newValue } }
    }
    var peripheralIdentifier: UUID? {
        get { defaults.string(forKey: "peripheralIdentifier").flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: "peripheralIdentifier") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        outputUID = defaults.string(forKey: "outputUID") ?? ""
        keepSystemInput = defaults.object(forKey: "keepSystemInput") == nil ? true : defaults.bool(forKey: "keepSystemInput")
        voiceKey = defaults.string(forKey: "voiceKey").flatMap(VoiceKey.init(rawValue:)) ?? .leftControl
        gainDB = defaults.double(forKey: "gainDB")
        whisperMode = defaults.bool(forKey: "whisperMode")
        whisperGainDB = defaults.object(forKey: "whisperGainDB") == nil ? 6 : defaults.double(forKey: "whisperGainDB")
    }
}

enum VoiceKey: String, CaseIterable, Identifiable {
    case leftControl, fn, rightOption, f20
    var id: Self { self }
    var usesToggle: Bool { self == .leftControl || self == .fn }
    var nativeMappingDestination: UInt64 { usesToggle ? 0 : hidUsage }
    var title: String {
        switch self {
        case .leftControl: return String(localized: "Left Control (WeChat toggle)")
        case .fn: return String(localized: "Fn / Globe (WeChat toggle)")
        case .rightOption: return String(localized: "Right Option")
        case .f20: return "F20"
        }
    }
    var hidUsage: UInt64 {
        switch self {
        case .leftControl: return 0x0000_0007_0000_00E0
        case .fn: return 0x0000_00FF_0000_0003
        case .rightOption: return 0x0000_0007_0000_00E6
        case .f20: return 0x0000_0007_0000_006F
        }
    }
}

enum XiaomiRemoteVariant {
    case rc003Pro
    static func detected(fromModelNumber value: String) -> Self? {
        value.trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines)).uppercased() == "RC003" ? .rc003Pro : nil
    }
}

// Protocol diagnostics are private OSLog entries; PCM and transcripts are never logged.
final class AppLogger {
    static let shared = AppLogger()
    private let logger = Logger(subsystem: "com.yangpan.MiRemoteHelper", category: "remote")
    func write(_ message: String) { logger.debug("\(message, privacy: .private)") }
}
