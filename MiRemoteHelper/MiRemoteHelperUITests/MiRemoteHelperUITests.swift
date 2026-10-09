import XCTest

final class MiRemoteHelperUITests: XCTestCase {
    @MainActor private func checkWorkspace(language: String, voice: String, mappings: String, login: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        app.launch()
        defer { app.terminate() }
        let voiceNavigation = app.buttons["navigation_voice"]
        XCTAssertTrue(voiceNavigation.waitForExistence(timeout: 10))
        XCTAssertEqual(voiceNavigation.label, voice)
        voiceNavigation.click()
        XCTAssertTrue(app.buttons["audioSettings"].exists)
        XCTAssertTrue(app.buttons["whisperMode"].exists)
        attachScreenshot(app, name: "Voice-\(language)")

        let mappingNavigation = app.buttons["navigation_mapping"]
        XCTAssertEqual(mappingNavigation.label, mappings)
        mappingNavigation.click()
        XCTAssertTrue(app.buttons["mapping_ok_doubleTap"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["mapping_ok_hold"].exists)
        let menu = app.buttons["mapping_ok_doubleTap"]
        menu.click()
        XCTAssertTrue(app.buttons["customShortcutAction"].exists)
        app.buttons["customShortcutAction"].click()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(app.sheets.firstMatch.exists)
        attachScreenshot(app, name: "Mappings-\(language)")

        app.buttons["openSettings"].click()
        let loginToggle = app.descendants(matching: .any)["launchAtLoginToggle"]
        XCTAssertTrue(loginToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(loginToggle.label, login)
        attachScreenshot(app, name: "Settings-\(language)")
    }

    @MainActor private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor func testEnglishWorkspace() {
        checkWorkspace(language: "en", voice: "Voice Input", mappings: "Button Mapping", login: "Launch at Login")
    }

    @MainActor func testSimplifiedChineseWorkspace() {
        checkWorkspace(language: "zh-Hans", voice: "语音输入", mappings: "按键映射", login: "登录时自动启动")
    }
}
