import AppKit
import CoreGraphics

/// Owns a latched app switcher and consumes remote keys until confirmation.
final class AppSwitcherSession {
    private let beginEvents: () -> Bool
    private let stepEvents: (Bool) -> Bool
    private let finishEvents: (Bool) -> Void
    private(set) var isActive = false
    private var suppressed = Set<RemoteButton>()

    init(begin: @escaping () -> Bool, step: @escaping (Bool) -> Bool, finish: @escaping (Bool) -> Void) {
        beginEvents = begin
        stepEvents = step
        finishEvents = finish
    }

    @discardableResult func begin(held: Set<RemoteButton>) -> Bool {
        guard !isActive else { return true }
        guard beginEvents() else { return false }
        isActive = true
        suppressed.formUnion(held)
        return true
    }

    /// Release edges stay consumed even when confirmation closes the switcher.
    func handle(pressed: Set<RemoteButton>, down: Set<RemoteButton>) -> Set<RemoteButton> {
        var consumed = suppressed
        if isActive {
            consumed.formUnion(pressed.subtracting([.microphone]))
            suppressed.formUnion(pressed.subtracting([.microphone]))
            if down.contains(.microphone) || down.contains(.back) || down.contains(.power) {
                finish(cancel: true)
            } else if down.contains(.ok) || down.contains(.home) {
                finish(cancel: false)
            } else if down.contains(.left) != down.contains(.right),
                      !stepEvents(down.contains(.left)) {
                finish(cancel: true)
            }
        }
        suppressed.formIntersection(pressed)
        return consumed
    }

    func finish(cancel: Bool) {
        guard isActive else { return }
        isActive = false
        finishEvents(cancel)
    }

    deinit { finish(cancel: true) }
}

/// A private event source keeps synthetic Command ownership separate from the keyboard.
final class AppSwitcherKeyboard {
    private let source = CGEventSource(stateID: .privateState)
    private var releaseEvent: CGEvent?
    private var commandHandoff = AppSwitcherCommandHandoff()
    var commandReleasePending: Bool { commandHandoff.isPending(at: ProcessInfo.processInfo.systemUptime) }

    static func commandEvent(source: CGEventSource?, down: Bool, physicalFlags: CGEventFlags) -> CGEvent? {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: down) else { return nil }
        event.type = .flagsChanged
        var flags = physicalFlags
        if down {
            flags.insert(.maskCommand)
            flags.insert(CGEventFlags(rawValue: UInt64(NX_DEVICELCMDKEYMASK)))
        }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: KeyboardInjector.syntheticEventMarker)
        return event
    }

    static func tabEvents(source: CGEventSource?, backward: Bool) -> [CGEvent]? {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 48, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 48, keyDown: false) else { return nil }
        down.flags = backward ? [.maskCommand, .maskShift] : .maskCommand
        up.flags = .maskCommand
        for event in [down, up] {
            event.setIntegerValueField(.eventSourceUserData, value: KeyboardInjector.syntheticEventMarker)
        }
        return [down, up]
    }

    static func releaseFlags(from flags: CGEventFlags) -> CGEventFlags {
        // HID flags can include the Command we injected. Echoing them in a
        // flagsChanged release leaves the switcher waiting for another key.
        var result = flags
        result.remove(.maskCommand)
        result.remove(CGEventFlags(rawValue: UInt64(NX_DEVICELCMDKEYMASK)))
        if result.contains(CGEventFlags(rawValue: UInt64(NX_DEVICERCMDKEYMASK))) {
            result.insert(.maskCommand)
        }
        return result
    }

    func begin() -> Bool {
        guard KeyboardInjector.isAccessibilityTrusted, let source,
              let down = Self.commandEvent(source: source, down: true, physicalFlags: CGEventSource.flagsState(.hidSystemState)),
              let up = Self.commandEvent(source: source, down: false, physicalFlags: []),
              let tabs = Self.tabEvents(source: source, backward: false) else { return false }
        releaseEvent = up
        for event in [down] + tabs { event.post(tap: .cghidEventTap) }
        return true
    }

    func step(backward: Bool) -> Bool {
        guard KeyboardInjector.isAccessibilityTrusted, releaseEvent != nil,
              let events = Self.tabEvents(source: source, backward: backward) else { return false }
        for event in events { event.post(tap: .cghidEventTap) }
        return true
    }

    func finish(cancel: Bool) {
        guard let release = releaseEvent else { return }
        releaseEvent = nil
        if cancel {
            for down in [true, false] {
                if let event = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: down) {
                    event.flags = .maskCommand
                    event.setIntegerValueField(.eventSourceUserData, value: KeyboardInjector.syntheticEventMarker)
                    event.post(tap: .cghidEventTap)
                }
            }
        }
        release.flags = Self.releaseFlags(from: CGEventSource.flagsState(.hidSystemState))
        release.post(tap: .cghidEventTap)
        commandHandoff.released(at: ProcessInfo.processInfo.systemUptime)
    }

    deinit { finish(cancel: true) }
}

/// A posted Command-up may not yet be reflected in the HID flags snapshot.
struct AppSwitcherCommandHandoff {
    private var releasedAt: TimeInterval?
    mutating func released(at time: TimeInterval) { releasedAt = time }
    func isPending(at time: TimeInterval) -> Bool {
        guard let releasedAt else { return false }
        return time >= releasedAt && time - releasedAt < 0.25
    }
}
