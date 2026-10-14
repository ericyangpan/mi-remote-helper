import SwiftUI

@main
struct MiRemoteHelperApp: App {
    @ObservedObject private var localization = AppLocalization.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model: BridgeModel

    init() {
        LegacyPreferencesMigration.run()
        _model = StateObject(wrappedValue: BridgeModel(settings: AppSettings(localization: .shared)))
    }

    var body: some Scene {
        Window("Mi Remote Helper", id: "main") {
            MainWindowView(model: model)
                .environment(\.locale, localization.locale)
                .onAppear { delegate.model = model }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands { AppInfoCommands() }
        Settings {
            AppSettingsView(model: model)
                .environment(\.locale, localization.locale)
        }
        Window(String.appLocalized("About Mi Remote Helper"), id: "about") {
            AboutView().environment(\.locale, localization.locale)
        }
        .windowResizability(.contentSize)
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(model.isSpeaking ? "MenuBarRemoteActive" : "MenuBarRemote")
                .renderingMode(.template)
                .accessibilityLabel(model.isSpeaking ? String.appLocalized("Mi Remote Helper, receiving audio") : "Mi Remote Helper")
        }
    }
}

private struct AppInfoCommands: Commands {
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            CenteredSettingsLink { Text(String.appLocalized("Settings…")) }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(replacing: .appInfo) {
            Button(String.appLocalized("About Mi Remote Helper")) { openWindow(id: "about") }
        }
    }
}

private struct MenuContent: View {
    @ObservedObject var model: BridgeModel
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(model.state.displayText)
        Button(String.appLocalized("Open Mi Remote Helper…")) { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button(model.isRunning ? String.appLocalized("Stop Voice Bridge") : String.appLocalized("Connect Remote")) { model.isRunning ? model.stop() : model.start() }
        Divider()
        Button(String.appLocalized("Quit")) { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var didFinishLaunching = false
    weak var model: BridgeModel? {
        didSet { startConnectionIfReady() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
        startConnectionIfReady()
        // Let macOS 26+ render the native Icon Composer asset and its system margins.
        if #unavailable(macOS 26), let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
    }
    private func startConnectionIfReady() {
        guard didFinishLaunching else { return }
        #if DEBUG
        // A hosted unit test must never connect to the user's physical remote.
        guard NSClassFromString("XCTestCase") == nil else { return }
        #endif
        model?.startAtLaunchIfNeeded()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        !MainWindowPlacement.shared.reopen()
    }
    func applicationWillTerminate(_ notification: Notification) { model?.stop() }
}
