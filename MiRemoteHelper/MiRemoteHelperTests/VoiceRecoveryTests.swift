import Foundation
import CoreGraphics
import Testing
@testable import MiRemoteHelper

struct VoiceRecoveryTests {
    @Test func orphanAudioNeverOwnsAPressAndStopRejectsTailPackets() {
        var edges = RemoteVoiceControlEdgeTracker()
        // Transport admits audio only during a control-owned press.
        #expect(!edges.isDown) // Audio arriving before MIC_OPEN is dropped.
        #expect(edges.update(active: true) == .down)
        #expect(edges.isDown) // Audio may now start the stream before STREAM_START.
        #expect(edges.update(active: true) == nil)
        #expect(edges.update(active: false) == .up)
        #expect(!edges.isDown) // Even tail audio arriving more than 0.3 s later is dropped.
        #expect(edges.update(active: true) == .down)
        #expect(edges.isDown) // No time-based suppression of a valid rapid next press.
        edges.cancelCurrentPress()
        #expect(!edges.isDown)
        edges.reset()
        #expect(!edges.isDown)
    }

    @Test func missingStreamAndStopTimeOutBeforeAnyAudio() {
        var watchdog = VoiceSessionWatchdog()
        watchdog.press(at: 10)
        #expect(watchdog.failure(at: 11.99) == nil)
        #expect(watchdog.failure(at: 12) == .startup)
        // Recovery resets the transport's edge tracker and permits another press.
        watchdog.reset()
        #expect(watchdog.failure(at: 100) == nil)
        watchdog.press(at: 100)
        watchdog.receivedAudio(at: 100.1)
        #expect(watchdog.failure(at: 101) == nil)
    }

    @Test func firstAudioChangesStartupDeadlineIntoStreamDeadline() {
        var watchdog = VoiceSessionWatchdog()
        watchdog.press(at: 0)
        watchdog.receivedAudio(at: 1.8)
        #expect(watchdog.failure(at: 2.1) == nil)
        #expect(watchdog.failure(at: 3.9) == .interrupted)
        watchdog.reset() // STOP, disconnect, or cancellation.
        watchdog.receivedAudio(at: 4) // Late PCM must not rearm the timer.
        #expect(watchdog.failure(at: 100) == nil)
    }

    @Test func bothCallbackOrdersReleaseCommandBeforeVoiceTap() {
        for hidFirst in [true, false] {
            for key in [VoiceKey.fn, .leftControl] {
                var now = 10.0
                var flags: CGEventFlags = .maskCommand
                var handoff = AppSwitcherCommandHandoff()
                var sent: [CGEventFlags] = []
                var releases: [() -> Void] = []
                var trace: [String] = []
                let switcher = AppSwitcherSession(begin: { true }, step: { _ in true }, finish: { _ in
                    trace.append("command-up")
                    handoff.released(at: now)
                    // Deliberately keep HID flags stale until after the Fn/Ctrl tap.
                })
                #expect(switcher.begin(held: []))
                if hidFirst {
                    _ = switcher.handle(pressed: [.microphone], down: [.microphone])
                    now += 0.01
                }
                // Same handoff used by ButtonMappingModel.prepareForVoiceInput.
                switcher.finish(cancel: true)
                let voice = VoiceToggleShortcut(ambientFlags: { flags }, postEvent: {
                    trace.append("voice-edge")
                    sent.append($0.flags)
                }, canStart: { true }, scheduleRelease: { releases.append($0) })
                #expect(voice.press(key: key, clearSwitcherCommand: handoff.isPending(at: now)))
                if !hidFirst { _ = switcher.handle(pressed: [.microphone], down: [.microphone]) }
                releases.removeFirst()()
                #expect(trace == ["command-up", "voice-edge", "voice-edge"])
                #expect(sent.allSatisfy { !$0.contains(.maskCommand) })
                #expect(sent[0].contains(key == .fn ? .maskSecondaryFn : .maskControl))
                #expect(sent[1].isEmpty)
                flags = []
                #expect(voice.release())
                releases.removeFirst()()
            }
        }
    }

    @Test func commandHandoffDoesNotStripLaterPhysicalCommandPresses() {
        var handoff = AppSwitcherCommandHandoff()
        #expect(!handoff.isPending(at: 10))
        handoff.released(at: 10)
        #expect(handoff.isPending(at: 10.1))
        #expect(!handoff.isPending(at: 10.3))
    }
}
