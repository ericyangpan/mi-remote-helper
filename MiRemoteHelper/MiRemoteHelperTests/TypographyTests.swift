import AppKit
import CoreText
import Testing
@testable import MiRemoteHelper

@MainActor
struct TypographyTests {
    @Test func bundledFontsLoadWithoutSubstitutionAndSupportChinese() throws {
        for face in AppTypography.Face.allCases {
            #expect(Bundle.main.url(forResource: face.resource, withExtension: "ttf") != nil)
            let font = AppTypography.nativeFont(face, size: 20)
            #expect(font.fontName == face.rawValue)
            let chinese = CTFontCreateForString(font as CTFont, "语音输入" as CFString, CFRange(location: 0, length: 4))
            #expect(CTFontCopyPostScriptName(chinese) as String == face.chineseName)
        }
        for family in ["Arvo", "Poppins"] {
            let url = try #require(Bundle.main.url(forResource: "\(family)-OFL", withExtension: "txt"))
            #expect(try String(contentsOf: url, encoding: .utf8).contains("SIL OPEN FONT LICENSE"))
        }
    }
}
