import ApplicationServices
import CoreGraphics
import Foundation
import IOKit.hidsystem

/// Owns one start/end pair. Duplicate ATVV controls must not toggle dictation.
final class HeldVoiceShortcut {
    private let send: (Bool) -> Bool
    private(set) var isHeld = false
    private(set) var generation: UInt64 = 0

    init(send: @escaping (Bool) -> Bool) { self.send = send }

    @discardableResult func press() -> Bool {
        guard !isHeld else { return true }
        guard send(true) else { return false }
        isHeld = true
        generation &+= 1
        return true
    }

    @discardableResult func release(ifGeneration expected: UInt64? = nil) -> Bool {
        if let expected, expected != generation { return true }
        guard isHeld else { return true }
        guard send(false) else { return false }
        isHeld = false
        generation &+= 1
        return true
    }
}

/// Serializes complete taps so a quick remote release cannot overlap key edges.
final class ControlTapSequencer {
    typealias Tap = (down: () -> Void, up: () -> Void)
    private let scheduleRelease: (@escaping () -> Void) -> Void
    private var queue: [Tap] = []
    private var pendingUp: (() -> Void)?
    private var generation: UInt64 = 0

    init(scheduleRelease: @escaping (@escaping () -> Void) -> Void) {
        self.scheduleRelease = scheduleRelease
    }

    @discardableResult func enqueue(_ tap: Tap) -> Bool {
        guard queue.count < 16 else { return false }
        queue.append(tap)
        startNext()
        return true
    }

    private func startNext() {
        guard pendingUp == nil, !queue.isEmpty else { return }
        let tap = queue.removeFirst()
        generation &+= 1
        let token = generation
        pendingUp = tap.up
        tap.down()
        scheduleRelease { [weak self] in
            guard let self, self.generation == token, let up = self.pendingUp else { return }
            self.pendingUp = nil
            up()
            self.startNext()
        }
    }

    /// Termination cannot leave a scheduled Ctrl-up or end tap undelivered.
    func finishImmediately() {
        generation &+= 1
        let up = pendingUp
        pendingUp = nil
        up?()
        let remaining = queue
        queue.removeAll()
        for tap in remaining { tap.down(); tap.up() }
    }
}

final class VoiceToggleShortcut {
    private var key: VoiceKey = .leftControl
    private var clearSwitcherCommand = false
    // A private source keeps this shortcut's state separate from physical keys.
    private let source = CGEventSource(stateID: .privateState)
    private let taps: ControlTapSequencer
    private let ambientFlags: () -> CGEventFlags
    private let postEvent: (CGEvent) -> Void
    private let canStart: () -> Bool

    init(ambientFlags: @escaping () -> CGEventFlags = { CGEventSource.flagsState(.hidSystemState) },
         postEvent: @escaping (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) },
         canStart: @escaping () -> Bool = { AXIsProcessTrusted() },
         scheduleRelease: @escaping (@escaping () -> Void) -> Void = { release in
             DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: release)
         }) {
        self.ambientFlags = ambientFlags
        self.postEvent = postEvent
        self.canStart = canStart
        taps = ControlTapSequencer(scheduleRelease: scheduleRelease)
    }
    private lazy var held = HeldVoiceShortcut { [weak self] down in self?.send(down) ?? false }
    var isHeld: Bool { held.isHeld }
    var generation: UInt64 { held.generation }
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult func press(key: VoiceKey = .leftControl, clearSwitcherCommand: Bool = false) -> Bool {
        guard key.usesToggle else { return false }
        guard !held.isHeld else { return self.key == key }
        self.key = key
        self.clearSwitcherCommand = clearSwitcherCommand
        return held.press()
    }
    @discardableResult func release(ifGeneration expected: UInt64? = nil) -> Bool { held.release(ifGeneration: expected) }
    func finishPendingTaps() { taps.finishImmediately() }

    static func event(source: CGEventSource?, down: Bool, ambientFlags: CGEventFlags,
                      key: VoiceKey = .leftControl) -> CGEvent? {
        guard key.usesToggle,
              let event = CGEvent(keyboardEventSource: source, virtualKey: key == .fn ? 63 : 59, keyDown: down) else { return nil }
        // Modifier-only shortcuts require flagsChanged, including the left-side
        // device flag. An ordinary keyUp is not equivalent to releasing Ctrl.
        event.type = .flagsChanged
        event.flags = flags(ambient: ambientFlags, down: down, key: key)
        event.setIntegerValueField(.eventSourceUserData, value: VoiceEventDiagnostics.marker)
        return event
    }

    private static func flags(ambient: CGEventFlags, down: Bool, key: VoiceKey) -> CGEventFlags {
        // HID flags also contain our own posted events. They are not a snapshot
        // of physical keys: a queued tap may see the preceding synthetic down.
        var flags = ambient
        if key == .fn {
            flags.remove(.maskSecondaryFn)
        } else {
            flags.remove(CGEventFlags(rawValue: UInt64(NX_DEVICELCTLKEYMASK)))
            if flags.rawValue & UInt64(NX_DEVICERCTLKEYMASK) == 0 { flags.remove(.maskControl) }
        }
        if down {
            if key == .fn { flags.insert(.maskSecondaryFn) }
            else {
                flags.insert(.maskControl)
                flags.insert(CGEventFlags(rawValue: UInt64(NX_DEVICELCTLKEYMASK)))
            }
        }
        return flags
    }

    private func send(_ starting: Bool) -> Bool {
        guard let source, !starting || canStart(),
              let down = Self.event(source: source, down: true, ambientFlags: [], key: key),
              let up = Self.event(source: source, down: false, ambientFlags: [], key: key) else { return false }
        // One complete tap starts dictation; a second ends it after audio drains.
        let tapKey = key
        let keyName = tapKey.rawValue
        let clearCommand = starting && clearSwitcherCommand
        let currentFlags = ambientFlags
        let readFlags = {
            let flags = currentFlags()
            return clearCommand ? AppSwitcherKeyboard.releaseFlags(from: flags) : flags
        }
        let post = postEvent
        return taps.enqueue((down: {
            down.flags = Self.flags(ambient: readFlags(), down: true, key: tapKey)
            VoiceEventDiagnostics.record("VOICE TAP key=\(keyName) phase=\(starting ? "start" : "end") edge=down flags=\(String(down.flags.rawValue, radix: 16))")
            post(down)
        }, up: {
            up.flags = Self.flags(ambient: readFlags(), down: false, key: tapKey)
            VoiceEventDiagnostics.record("VOICE TAP key=\(keyName) phase=\(starting ? "start" : "end") edge=up flags=\(String(up.flags.rawValue, radix: 16))")
            post(up)
        }))
    }
}
