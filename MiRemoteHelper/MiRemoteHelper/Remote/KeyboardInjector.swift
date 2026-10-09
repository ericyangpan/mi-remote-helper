import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum KeyboardInjector {
    static let syntheticEventMarker: Int64 = 0x5849_414F

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func send(_ action: ButtonAction) -> Bool {
        guard action != .disabled else { return true }
        guard isAccessibilityTrusted else { return false }

        switch action {
        case .disabled:
            return true
        case .escape:
            return postKey(code: 53)
        case .returnKey:
            return postKey(code: 36)
        case .arrowUp:
            return postKey(code: 126)
        case .arrowDown:
            return postKey(code: 125)
        case .arrowLeft:
            return postKey(code: 123)
        case .arrowRight:
            return postKey(code: 124)
        case .homeKey:
            return postKey(code: 115)
        case .endKey:
            return postKey(code: 119)
        case .pageUp:
            return postKey(code: 116)
        case .pageDown:
            return postKey(code: 121)
        case .deleteBackward:
            return postKey(code: 51)
        case .clearText:
            return clearFocusedText()
        case .showDesktop:
            return postKey(code: 103, flags: .maskSecondaryFn)
        case .contextMenu, .mouseRightClick:
            return postRightClick()
        case .appSwitcher:
            return postKey(code: 48, flags: .maskCommand)
        case .volumeUp:
            return postSystemKey(type: 0)
        case .volumeDown:
            return postSystemKey(type: 1)
        case .volumeMute:
            return postSystemKey(type: 7)
        case .playPause:
            return postSystemKey(type: 16)
        }
    }

    @discardableResult
    static func send(_ binding: ButtonBinding) -> Bool {
        switch binding {
        case let .preset(action): return send(action)
        case let .shortcut(chord): return send(chord)
        case .dictation: return true
        }
    }

    @discardableResult
    static func send(_ chord: KeyChord) -> Bool {
        guard chord.isValid, isAccessibilityTrusted else { return false }
        return postKey(code: chord.keyCode, flags: cgFlags(for: chord.modifiers))
    }

    private static func cgFlags(for modifiers: KeyChord.Modifiers) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        return flags
    }

    private static func postKey(code: CGKeyCode, flags: CGEventFlags = []) -> Bool {
        guard let events = keyEvents(code: code, flags: flags) else { return false }
        for event in events { event.post(tap: .cghidEventTap) }
        return true
    }

    private static func keyEvents(code: CGKeyCode, flags: CGEventFlags = []) -> [CGEvent]? {
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        else { return nil }
        down.flags = flags
        up.flags = flags
        down.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        up.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        return [down, up]
    }

    static func clearTextEvents() -> [CGEvent]? {
        guard let selectAll = keyEvents(code: 0, flags: .maskCommand),
              let delete = keyEvents(code: 51) else { return nil }
        return selectAll + delete
    }

    private static func clearFocusedText() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return true }
        let target = AXUIElementCreateApplication(app.processIdentifier)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(target, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return true }
        let element = unsafeBitCast(focused, to: AXUIElement.self)
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
              let role = role as? String,
              [kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String].contains(role)
        else { return true }
        guard let events = clearTextEvents(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return false }
        // Keep both keystrokes ordered and addressed to the same application.
        // Delete has no Command modifier, so this never becomes Command-Delete.
        for event in events { event.postToPid(app.processIdentifier) }
        return true
    }

    /// Posts a single real right-click (down + up) at the current mouse cursor
    /// position. The cursor location is read from a null `CGEvent(source:)` — the
    /// CoreGraphics event coordinate space — instead of `NSEvent.mouseLocation`,
    /// whose bottom-left AppKit coordinates would land the click in the wrong place.
    /// Any failure to build the event source, the location probe, or either mouse
    /// event returns `false` so the HID path fails closed rather than faking success.
    private static func postRightClick() -> Bool {
        guard let source = CGEventSource(stateID: .privateState),
              let locationProbe = CGEvent(source: source)
        else { return false }
        let location = locationProbe.location
        guard let down = CGEvent(
                  mouseEventSource: source,
                  mouseType: .rightMouseDown,
                  mouseCursorPosition: location,
                  mouseButton: .right
              ),
              let up = CGEvent(
                  mouseEventSource: source,
                  mouseType: .rightMouseUp,
                  mouseCursorPosition: location,
                  mouseButton: .right
              )
        else { return false }
        down.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        up.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    private static func postSystemKey(type: Int32) -> Bool {
        func event(_ down: Bool) -> CGEvent? {
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
                subtype: 8, data1: Int((type << 16) | ((down ? 0xA : 0xB) << 8)), data2: -1)?.cgEvent
        }
        guard let down = event(true), let up = event(false) else { return false }
        for event in [down, up] {
            event.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
            event.post(tap: .cghidEventTap)
        }
        return true
    }
}
