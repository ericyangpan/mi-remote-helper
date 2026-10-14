import AppKit
import SwiftUI

/// All Settings entry points capture their source window before opening the scene.
struct CenteredSettingsLink<Label: View>: View {
    @Environment(\.openSettings) private var openSettings
    @ViewBuilder var label: Label

    var body: some View {
        Button {
            SettingsWindowPlacement.shared.prepare()
            openSettings()
        } label: { label }
    }
}

@MainActor
private final class SettingsWindowPlacement {
    static let shared = SettingsWindowPlacement()
    weak var settingsWindow: NSWindow?
    private var requested = false
    private var anchor: CGRect?
    private var visibleFrame: CGRect?

    func prepare() {
        let source = NSApp.keyWindow.flatMap { $0 === settingsWindow ? nil : $0 }
            ?? NSApp.windows.first { $0.isVisible && !$0.isMiniaturized && $0 !== settingsWindow }
        anchor = source?.frame
        visibleFrame = (source?.screen ?? NSScreen.main)?.visibleFrame
        requested = true
        // Existing Settings windows do not recreate their content when reopened.
        DispatchQueue.main.async { [weak self] in self?.placeIfRequested() }
    }

    func attach(_ window: NSWindow) {
        settingsWindow = window
        placeIfRequested()
    }

    private func placeIfRequested() {
        guard requested, let window = settingsWindow else { return }
        requested = false
        guard let anchor = anchor ?? visibleFrame else { window.center(); return }
        let size = window.frame.size
        var origin = CGPoint(x: anchor.midX - size.width / 2,
                             y: anchor.midY - size.height / 2)
        if let visibleFrame {
            origin.x = max(visibleFrame.minX, min(origin.x, visibleFrame.maxX - size.width))
            origin.y = max(visibleFrame.minY, min(origin.y, visibleFrame.maxY - size.height))
        }
        window.setFrameOrigin(origin)
    }
}

struct SettingsWindowReader: NSViewRepresentable {
    var language: AppLanguage
    final class WindowView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async {
                window.title = "Mi Remote Helper — " + String.appLocalized("Settings")
                SettingsWindowPlacement.shared.attach(window)
            }
        }
    }

    func makeNSView(context: Context) -> WindowView { WindowView() }
    func updateNSView(_ nsView: WindowView, context: Context) {
        nsView.window?.title = "Mi Remote Helper — " + String.appLocalized("Settings")
    }
}
