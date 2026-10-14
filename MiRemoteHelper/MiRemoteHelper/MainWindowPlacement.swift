import AppKit
import SwiftUI

/// Preserves the last display when the menu-bar app's main window is closed.
@MainActor
final class MainWindowPlacement {
    static let shared = MainWindowPlacement()
    weak var window: NSWindow?
    var openMainWindow: (() -> Void)?
    private var screenID: NSNumber?
    private var centerOnReopen = false
    private var observers: [NSObjectProtocol] = []

    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        self.window = window
        observers = [
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                object: window, queue: .main) { [weak self, weak window] _ in
                    guard let self, let window else { return }
                    self.screenID = window.screen?.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? NSNumber
                    self.centerOnReopen = true
                },
            NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification,
                object: window, queue: .main) { [weak self] _ in
                    DispatchQueue.main.async { self?.placeOnReopen() }
                }
        ]
        placeOnReopen()
    }

    /// Dock reopening should open the main scene even if Settings is visible.
    func reopen() -> Bool {
        guard let openMainWindow else { return false }
        if window?.isVisible == true {
            if window?.isMiniaturized == true { window?.deminiaturize(nil) }
            window?.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow()
            DispatchQueue.main.async { [weak self] in self?.placeOnReopen() }
        }
        return true
    }

    private func placeOnReopen() {
        guard centerOnReopen, let window, window.isVisible else { return }
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? NSNumber) == screenID
        } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        centerOnReopen = false
        let bounds = screen.visibleFrame
        window.setFrameOrigin(CGPoint(
            x: max(bounds.minX, bounds.midX - window.frame.width / 2),
            y: max(bounds.minY, bounds.midY - window.frame.height / 2)))
    }
}

struct MainWindowReader: NSViewRepresentable {
    final class WindowView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async { MainWindowPlacement.shared.attach(window) }
        }
    }

    func makeNSView(context: Context) -> WindowView { WindowView() }
    func updateNSView(_ nsView: WindowView, context: Context) {}
}
