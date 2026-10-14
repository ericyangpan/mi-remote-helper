import Foundation
import Combine

/// Uses explicit language bundles; switching never resets a window or bridge.
final class AppLocalization: ObservableObject {
    static let shared = AppLocalization()
    let objectWillChange = ObservableObjectPublisher()
    private let lock = NSLock()
    private var choice: AppLanguage
    private var selectedCode: String
    var language: AppLanguage {
        get { lock.lock(); defer { lock.unlock() }; return choice }
        set {
            let code = Self.code(for: newValue)
            lock.lock()
            let changed = choice != newValue || selectedCode != code
            choice = newValue
            selectedCode = code
            lock.unlock()
            // Subscribers must see the new bundle/locale as soon as notified.
            if changed { objectWillChange.send() }
        }
    }
    private let bundles: [String: Bundle]
    // Keep already-published status/error text translatable, including interpolation.
    private struct RenderedText {
        let translations: [String: String]
        var lastUse: UInt64
    }
    private var rendered: [String: RenderedText] = [:]
    private var useCounter: UInt64 = 0
    var locale: Locale { Locale(identifier: code) }
    private var code: String {
        lock.lock(); defer { lock.unlock() }
        return selectedCode
    }

    init(language: AppLanguage? = nil, bundle: Bundle = .main) {
        let choice = language ?? UserDefaults.standard.string(forKey: "appLanguage")
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
        self.choice = choice
        selectedCode = Self.code(for: choice)
        bundles = Dictionary(uniqueKeysWithValues: ["en", "zh-Hans"].map { code in
            (code, bundle.url(forResource: code, withExtension: "lproj").flatMap(Bundle.init(url:)) ?? bundle)
        })
    }

    static func code(for language: AppLanguage) -> String {
        if let code = language.languageCode { return code }
        // Read the system domain, ignoring this app's persisted AppleLanguages override.
        let preferences = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String] ?? []
        return Bundle.preferredLocalizations(from: ["en", "zh-Hans"], forPreferences: preferences).first ?? "en"
    }

    func string(_ value: String.LocalizationValue) -> String {
        let language = code
        return String(localized: value, bundle: bundles[language] ?? bundles["en"]!,
                      locale: Locale(identifier: language))
    }

    /// Only persisted-in-memory status text needs both rendered translations.
    /// Ordinary view labels render once in the currently selected language.
    func status(_ value: String.LocalizationValue) -> String {
        let translations = Dictionary(uniqueKeysWithValues: bundles.map { language, bundle in
            (language, String(localized: value, bundle: bundle, locale: Locale(identifier: language)))
        })
        return remember(translations)
    }

    func format(_ value: String.LocalizationValue, seconds: Double) -> String {
        let translations = Dictionary(uniqueKeysWithValues: bundles.map { language, bundle in
            let locale = Locale(identifier: language)
            return (language, String(format: String(localized: value, bundle: bundle, locale: locale), locale: locale, seconds))
        })
        return remember(translations)
    }

    private func remember(_ translations: [String: String]) -> String {
        lock.lock(); defer { lock.unlock() }
        useCounter &+= 1
        for text in translations.values {
            rendered[text] = RenderedText(translations: translations, lastUse: useCounter)
        }
        // Evict only the least recently used entry, preserving visible statuses.
        while rendered.count > 1_024, let oldest = rendered.min(by: { $0.value.lastUse < $1.value.lastUse })?.key {
            rendered.removeValue(forKey: oldest)
        }
        return translations[selectedCode] ?? translations["en"] ?? ""
    }

    func display(_ text: String) -> String {
        lock.lock(); defer { lock.unlock() }
        guard var entry = rendered[text] else { return text }
        useCounter &+= 1
        entry.lastUse = useCounter
        rendered[text] = entry
        return entry.translations[selectedCode] ?? text
    }
}

extension String {
    static func appLocalized(_ value: String.LocalizationValue) -> String {
        AppLocalization.shared.string(value)
    }
    static func appStatus(_ value: String.LocalizationValue) -> String {
        AppLocalization.shared.status(value)
    }
    var appTranslated: String { AppLocalization.shared.display(self) }
}
