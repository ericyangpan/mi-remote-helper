// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Open Voice Bridge, Copyright (C) 2026 Open Voice Bridge contributors.
// Reference: 1796b149f752ff2d2fa82fd818f8a5a2bc60802a. See THIRD_PARTY_NOTICES.md.

enum RemoteEventEdge { case down, up }

struct RemoteVoiceControlEdgeTracker {
    private enum Phase {
        case idle
        case down
        case draining
    }

    private var phase: Phase = .idle
    var isDown: Bool { phase == .down }

    mutating func update(active: Bool) -> RemoteEventEdge? {
        switch (phase, active) {
        case (.idle, true):
            phase = .down
            return .down
        case (.down, false):
            phase = .idle
            return .up
        case (.draining, false):
            // A pause cancelled this physical press. Consume its final STOP and
            // only then admit a fresh press; never synthesize an orphan release.
            phase = .idle
            return nil
        case (.idle, false), (.down, true), (.draining, true):
            return nil
        }
    }

    /// Cancels a press that is already active while preserving enough state to
    /// drain a duplicate STREAM_START and its eventual STOP. A clean idle tracker
    /// remains immediately usable so ATVV can still recognise a later restore
    /// double-click while the bridge is paused.
    mutating func cancelCurrentPress() {
        if phase == .down { phase = .draining }
    }

    /// A transport/session reset starts a new generation and therefore does not
    /// need to drain controls from the old one.
    mutating func reset() {
        phase = .idle
    }
}


enum ATVVVoiceBridgeGate {
    static func allowsVoice(bridgingEnabled: Bool) -> Bool { bridgingEnabled }
}
