import Foundation

/// Observes physical gestures even when no double-press action is assigned.
/// This never delays or dispatches mapped actions.
struct ButtonGestureFeedback {
    private struct Press {
        let started: TimeInterval
        let second: Bool
    }
    private var presses: [RemoteButton: Press] = [:]
    private var pending: (button: RemoteButton, deadline: TimeInterval)?

    mutating func begin(_ button: RemoteButton, at time: TimeInterval) {
        guard presses[button] == nil else { return }
        let second = pending.map { $0.button == button && time < $0.deadline } ?? false
        pending = nil
        guard button != .microphone else { return }
        presses[button] = Press(started: time, second: second)
    }

    mutating func release(_ button: RemoteButton, at time: TimeInterval) -> ButtonPressKind? {
        guard let press = presses.removeValue(forKey: button) else { return nil }
        if time - press.started >= ButtonPressTracker.holdDuration { return .hold }
        if press.second { return .doubleTap }
        pending = (button, time + ButtonPressTracker.doubleDuration)
        return .tap
    }

    mutating func cancel() {
        presses.removeAll()
        pending = nil
    }
}
