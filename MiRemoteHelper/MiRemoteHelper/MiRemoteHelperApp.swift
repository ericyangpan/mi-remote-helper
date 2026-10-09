import SwiftUI

@main
struct MiRemoteHelperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model: BridgeModel

    init() {
        LegacyPreferencesMigration.run()
        _model = StateObject(wrappedValue: BridgeModel())
    }

    var body: some Scene {
        Window("Mi Remote Helper", id: "main") {
            MainWindowView(model: model)
                .onAppear { delegate.model = model }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands { AppInfoCommands() }
        Settings {
            AppSettingsView(model: model)
        }
        Window(String(localized: "About Mi Remote Helper"), id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(model.isSpeaking ? "MenuBarRemoteActive" : "MenuBarRemote")
                .renderingMode(.template)
                .accessibilityLabel(model.isSpeaking ? String(localized: "Mi Remote Helper, receiving audio") : "Mi Remote Helper")
        }
    }
}

private struct AppInfoCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(String(localized: "About Mi Remote Helper")) { openWindow(id: "about") }
        }
    }
}

private struct MenuContent: View {
    @ObservedObject var model: BridgeModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(model.state.displayText)
        Button(String(localized: "Open Mi Remote Helper…")) { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button(model.isRunning ? String(localized: "Stop Voice Bridge") : String(localized: "Connect Remote")) { model.isRunning ? model.stop() : model.start() }
        Divider()
        Button(String(localized: "Quit")) { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: BridgeModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Let macOS 26+ render the native Icon Composer asset and its system margins.
        if #unavailable(macOS 26), let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { model?.stop() }
}
