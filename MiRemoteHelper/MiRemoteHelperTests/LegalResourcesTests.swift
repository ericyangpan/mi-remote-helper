import Foundation
import Testing
@testable import MiRemoteHelper

struct LegalResourcesTests {
    @Test func chineseNoticesAreBundledAndLicenseRemainsOriginal() {
        let chinese = LegalDocument.notices.contents(preferredLanguages: ["zh-Hans"])
        #expect(chinese.contains("第三方声明"))
        #expect(chinese.contains("1796b149f752ff2d2fa82fd818f8a5a2bc60802a"))
        #expect(LegalDocument.notices.contents(preferredLanguages: ["fr"]).contains("RC003 product photo"))
        #expect(LegalDocument.license.contents(preferredLanguages: ["zh-Hans"]) == LegalDocument.license.contents(preferredLanguages: ["en"]))
    }

    @Test func distributionContainsLicenseAndUpstreamNotices() throws {
        let license = LegalDocument.license.contents
        #expect(license.contains("GNU GENERAL PUBLIC LICENSE"))
        #expect(license.contains("Version 3, 29 June 2007"))
        let notices = LegalDocument.notices.contents(preferredLanguages: ["en"])
        #expect(notices.contains("1796b149f752ff2d2fa82fd818f8a5a2bc60802a"))
        #expect(notices.contains("remote-bridge-hub"))
        #expect(notices.contains("RC003 product photo"))
    }
}
