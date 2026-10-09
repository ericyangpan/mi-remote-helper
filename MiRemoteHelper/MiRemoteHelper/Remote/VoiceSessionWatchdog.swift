import Foundation

/// Monotonic deadlines cover both opening the mic and stalled audio delivery.
struct VoiceSessionWatchdog {
    enum Failure { case startup, interrupted }
    private var pressedAt: TimeInterval?
    private var lastAudioAt: TimeInterval?
    static let timeout: TimeInterval = 2

    mutating func press(at time: TimeInterval) {
        pressedAt = time
        lastAudioAt = nil
    }
    mutating func receivedAudio(at time: TimeInterval) {
        guard pressedAt != nil else { return }
        lastAudioAt = time
    }
    mutating func reset() { pressedAt = nil; lastAudioAt = nil }
    func failure(at time: TimeInterval) -> Failure? {
        guard let pressedAt, time - (lastAudioAt ?? pressedAt) >= Self.timeout else { return nil }
        return lastAudioAt == nil ? .startup : .interrupted
    }
}
