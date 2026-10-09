import Foundation
import Testing
@testable import MiRemoteHelper

struct LocalizationTests {
    private func languageBundle(_ language: String) throws -> Bundle {
        let url = try #require(Bundle(for: AppSettings.self).url(forResource: language, withExtension: "lproj"))
        return try #require(Bundle(url: url))
    }

    @Test func packagedTranslationsCoverBothLanguages() throws {
        for table in ["Localizable", "InfoPlist"] {
            var tables: [[String: String]] = []
            for language in ["en", "zh-Hans"] {
                let bundle = try languageBundle(language)
                let url = try #require(bundle.url(forResource: table, withExtension: "strings"))
                let data = try Data(contentsOf: url)
                let entries = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
                #expect(!entries.isEmpty)
                #expect(entries.values.allSatisfy { !$0.isEmpty })
                tables.append(entries)
            }
            #expect(Set(tables[0].keys) == Set(tables[1].keys))
        }
    }

    @Test func localizedInterpolationKeepsDeviceNamesAndDuration() throws {
        let english = try languageBundle("en")
        let chinese = try languageBundle("zh-Hans")
        let press = "长按"
        let button = "返回"
        #expect(String(localized: "Record \(press) shortcut for \(button)", bundle: chinese) == "录制返回的长按快捷键")
        let name = "RC003"
        #expect(String(localized: "Connected to \(name)", bundle: english) == "Connected to RC003")
        #expect(String(localized: "Connected to \(name)", bundle: chinese) == "已连接 RC003")
        let duration = String(localized: "%.1f s", bundle: chinese)
        #expect(String(format: duration, locale: Locale(identifier: "zh_CN"), 1.25) == "1.2 秒")
        let result: Int32 = -50
        #expect(String(localized: "Unable to connect to the virtual microphone (\(result)).", bundle: chinese) == "无法连接虚拟麦克风（-50）。")
        #expect(chinese.localizedString(forKey: "NSBluetoothAlwaysUsageDescription", value: nil, table: "InfoPlist") == "连接小米遥控器，接收按住语音键时的麦克风声音。")
        #expect(english.localizedString(forKey: "NSBluetoothAlwaysUsageDescription", value: nil, table: "InfoPlist").contains("Xiaomi remote"))
    }
}
