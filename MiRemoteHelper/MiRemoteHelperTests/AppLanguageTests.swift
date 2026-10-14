import Foundation
import Testing
import Combine
@testable import MiRemoteHelper

struct AppLanguageTests {
    @Test func choicePersistsWithoutChangingOtherSettings() throws {
        let suite = "MiRemoteHelper.LanguageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.appLanguage == .system)
        settings.appLanguage = .simplifiedChinese
        #expect(defaults.stringArray(forKey: "AppleLanguages") == ["zh-Hans"])
        let relaunched = AppSettings(defaults: defaults)
        #expect(relaunched.appLanguage == .simplifiedChinese)
        relaunched.appLanguage = .english
        #expect(defaults.stringArray(forKey: "AppleLanguages") == ["en"])
    }

    @Test func languageSwitchTranslatesExistingInterpolatedStatusImmediately() throws {
        let localization = AppLocalization(language: .english, bundle: Bundle(for: AppSettings.self))
        let name = "RC003"
        let status = localization.status("Connected to \(name)")
        #expect(status == "Connected to RC003")
        let duration = localization.format("Received %.1f seconds of audio. WeChat Input handles transcription.", seconds: 1.2)
        localization.language = .simplifiedChinese
        #expect(localization.string("Settings") == "设置")
        #expect(localization.display(duration) == localization.format("Received %.1f seconds of audio. WeChat Input handles transcription.", seconds: 1.2))
        #expect(localization.display(status) == "已连接 RC003")
        localization.language = .english
        #expect(localization.display("已连接 RC003") == status)
        #expect(localization.display("BlackHole 2ch") == "BlackHole 2ch")
    }

    @Test func subscribersSeeTheNewLanguageWhenNotified() {
        let localization = AppLocalization(language: .english, bundle: Bundle(for: AppSettings.self))
        var observed = ""
        let subscription = localization.objectWillChange.sink {
            observed = localization.string("Settings")
        }
        localization.language = .simplifiedChinese
        #expect(observed == "设置")
        withExtendedLifetime(subscription) {}
    }

    @Test func settingsSynchronizeLanguageWithoutAnOpenSettingsView() throws {
        let suite = "MiRemoteHelper.LanguageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(AppLanguage.simplifiedChinese.rawValue, forKey: "appLanguage")
        let localization = AppLocalization(language: .english, bundle: Bundle(for: AppSettings.self))
        let settings = AppSettings(defaults: defaults, localization: localization)
        #expect(localization.string("Settings") == "设置")
        settings.appLanguage = .english
        #expect(localization.string("Settings") == "Settings")
    }

    @Test func viewRenderingCannotEvictAnExistingStatus() {
        let localization = AppLocalization(language: .english, bundle: Bundle(for: AppSettings.self))
        let status = localization.status("Connected to RC003")
        // Use a translated key with changing interpolation, as list rows do.
        let name = "RC003"
        let translated = localization.status("Connected to \(name)")
        for index in 0..<1100 {
            let button = "Button \(index)"
            _ = localization.string("Record shortcut for \(button)")
        }
        localization.language = .simplifiedChinese
        #expect(localization.display(translated) == "已连接 RC003")
        #expect(!status.isEmpty)
    }

    @Test func recentlyDisplayedStatusSurvivesCachePressure() {
        let localization = AppLocalization(language: .english, bundle: Bundle(for: AppSettings.self))
        let name = "RC003"
        let status = localization.status("Connected to \(name)")
        for index in 0..<1100 {
            _ = localization.display(status)
            let other = "Other \(index)"
            _ = localization.status("Connected to \(other)")
        }
        localization.language = .simplifiedChinese
        #expect(localization.display(status) == "已连接 RC003")
    }

    @Test func followingSystemRemovesOnlyAppLanguageOverride() throws {
        let suite = "MiRemoteHelper.LanguageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("virtual-device", forKey: "outputUID")
        let settings = AppSettings(defaults: defaults)
        settings.appLanguage = .english
        settings.appLanguage = .system
        #expect(defaults.persistentDomain(forName: suite)?["AppleLanguages"] == nil)
        #expect(settings.outputUID == "virtual-device")
        #expect(AppSettings(defaults: defaults).appLanguage == .system)
    }

    @Test func invalidPreferenceFallsBackToSystemWithoutChangingSavedMappings() throws {
        let suite = "MiRemoteHelper.LanguageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("unsupported", forKey: "appLanguage")
        defaults.set(Data([1, 2, 3]), forKey: "buttonMappings.v1")
        #expect(AppSettings(defaults: defaults).appLanguage == .system)
        #expect(defaults.data(forKey: "buttonMappings.v1") == Data([1, 2, 3]))
    }
}
