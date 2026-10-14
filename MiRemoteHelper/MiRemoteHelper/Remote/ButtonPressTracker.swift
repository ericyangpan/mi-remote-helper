import Foundation

/// Only bindings with a double press delay a single tap; holds never emit taps.
struct ButtonPressTracker {
    static let holdDuration: TimeInterval = 0.5
    static let doubleDuration: TimeInterval = 0.3
    private struct Press {
        let generation: UInt64
        let started: TimeInterval
        let tap: ButtonBinding
        let hold: ButtonBinding
        let doubleTap: ButtonBinding
        let isSecond: Bool
        var fired = false
    }
    private struct Pending {
        let deadline: TimeInterval
        let tap: ButtonBinding
        let doubleTap: ButtonBinding
    }
    private var presses: [RemoteButton: Press] = [:]
    private var pending: [RemoteButton: Pending] = [:]
    private var generation: UInt64 = 0

    var pendingButtons: [RemoteButton] { pending.keys.sorted { pending[$0]!.deadline < pending[$1]!.deadline } }
    func deadline(for button: RemoteButton) -> TimeInterval? { pending[button]?.deadline }

    mutating func begin(_ button: RemoteButton, tap: ButtonBinding, hold: ButtonBinding,
                        doubleTap: ButtonBinding = .preset(.disabled), at time: TimeInterval, allowVoice: Bool = false) -> UInt64? {
        guard (button != .microphone || allowVoice), presses[button] == nil else { return nil }
        let first = pending[button]
        let isSecond = first.map { time < $0.deadline } ?? false
        if isSecond { pending.removeValue(forKey: button) }
        generation &+= 1
        presses[button] = Press(generation: generation, started: time, tap: tap, hold: hold,
                               doubleTap: isSecond ? first!.doubleTap : doubleTap, isSecond: isSecond)
        return generation
    }

    mutating func fire(_ button: RemoteButton, generation: UInt64, at time: TimeInterval) -> ButtonBinding? {
        guard let press = presses[button], press.generation == generation, !press.fired,
              time - press.started >= Self.holdDuration else { return nil }
        presses[button]?.fired = true
        return press.hold
    }

    mutating func release(_ button: RemoteButton, at time: TimeInterval) -> ButtonBinding? {
        guard let press = presses.removeValue(forKey: button), !press.fired else { return nil }
        if time - press.started >= Self.holdDuration { return press.hold }
        if press.isSecond { return press.doubleTap }
        if !press.doubleTap.isDisabled {
            pending[button] = Pending(deadline: time + Self.doubleDuration, tap: press.tap, doubleTap: press.doubleTap)
            return nil
        }
        return press.tap
    }

    mutating func flush(_ button: RemoteButton, at time: TimeInterval, force: Bool = false) -> ButtonBinding? {
        guard let first = pending[button], force || time >= first.deadline else { return nil }
        pending.removeValue(forKey: button)
        return first.tap
    }

    mutating func cancel() { presses.removeAll(); pending.removeAll() }
}
