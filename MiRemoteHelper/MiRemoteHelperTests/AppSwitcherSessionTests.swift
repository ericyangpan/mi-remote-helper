import AppKit
import CoreGraphics
import Testing
@testable import MiRemoteHelper

struct AppSwitcherSessionTests {
    @Test func confirmationClearsInjectedCommandInsteadOfEchoingIt() {
        let left = CGEventFlags(rawValue: UInt64(NX_DEVICELCMDKEYMASK))
        let right = CGEventFlags(rawValue: UInt64(NX_DEVICERCMDKEYMASK))
        #expect(AppSwitcherKeyboard.releaseFlags(from: [.maskCommand, left]) == [])
        #expect(AppSwitcherKeyboard.releaseFlags(from: [.maskCommand, left, .maskShift]) == .maskShift)
        #expect(AppSwitcherKeyboard.releaseFlags(from: [.maskCommand, left, right]) == [.maskCommand, right])
    }
    @Test func navigationStaysOpenUntilConfirmationAndConsumesRelease() {
        var starts = 0
        var steps: [Bool] = []
        var finishes: [Bool] = []
        let session = AppSwitcherSession(begin: { starts += 1; return true },
            step: { steps.append($0); return true }, finish: { finishes.append($0) })
        #expect(session.begin(held: []))
        #expect(session.handle(pressed: [.right], down: [.right]) == [.right])
        #expect(session.handle(pressed: [.right], down: []).contains(.right))
        #expect(session.handle(pressed: [], down: []) == [.right])
        #expect(session.handle(pressed: [.left], down: [.left]) == [.left])
        _ = session.handle(pressed: [], down: [])
        #expect(session.isActive)
        #expect(steps == [false, true])
        #expect(starts == 1)
        #expect(session.handle(pressed: [.ok], down: [.ok]) == [.ok])
        #expect(!session.isActive)
        #expect(finishes == [false])
        #expect(session.handle(pressed: [], down: []) == [.ok])
        #expect(session.handle(pressed: [.left], down: [.left]).isEmpty)
    }

    @Test func cancellationAndHomeConfirmationDoNotLeakOtherBindings() {
        for button in [RemoteButton.back, .power, .home, .microphone] {
            var finishes: [Bool] = []
            let session = AppSwitcherSession(begin: { true }, step: { _ in true }, finish: { finishes.append($0) })
            #expect(session.begin(held: [.up]))
            let consumed = session.handle(pressed: [.up, button], down: [button, .right])
            #expect(consumed.contains(.up))
            #expect(consumed.contains(button) == (button != .microphone))
            #expect(finishes == [button != .home])
            session.finish(cancel: true)
            #expect(finishes.count == 1)
            #expect(session.handle(pressed: [], down: []).contains(.up))
        }
    }

    @Test func failuresAndDisconnectReleaseSessionExactlyOnce() {
        let failed = AppSwitcherSession(begin: { false }, step: { _ in true }, finish: { _ in Issue.record("No modifier was acquired") })
        #expect(!failed.begin(held: []))
        #expect(!failed.isActive)
        for failStep in [false, true] {
            var finishes: [Bool] = []
            let session = AppSwitcherSession(begin: { true }, step: { _ in !failStep }, finish: { finishes.append($0) })
            #expect(session.begin(held: []))
            _ = session.handle(pressed: [.right], down: [.right])
            session.finish(cancel: true)
            session.finish(cancel: true)
            #expect(finishes == [true])
            #expect(session.handle(pressed: [], down: []) == [.right])
        }
    }

    @Test func tabDirectionAndCommandReleaseEventsHaveCorrectFlags() throws {
        let source = try #require(CGEventSource(stateID: .privateState))
        for backward in [false, true] {
            let events = try #require(AppSwitcherKeyboard.tabEvents(source: source, backward: backward))
            #expect(events.map(\.type) == [.keyDown, .keyUp])
            #expect(events.allSatisfy { $0.getIntegerValueField(.keyboardEventKeycode) == 48 })
            #expect(events[0].flags.contains(.maskShift) == backward)
            #expect(events[1].flags == .maskCommand)
            #expect(events.allSatisfy { $0.getIntegerValueField(.eventSourceUserData) == KeyboardInjector.syntheticEventMarker })
        }
        let press = try #require(AppSwitcherKeyboard.commandEvent(source: source, down: true, physicalFlags: []))
        let release = try #require(AppSwitcherKeyboard.commandEvent(source: source, down: false, physicalFlags: .maskShift))
        #expect(press.type == .flagsChanged && press.flags.contains(.maskCommand))
        #expect(release.type == .flagsChanged && release.flags == .maskShift)
        #expect(release.getIntegerValueField(.keyboardEventKeycode) == 55)
    }
}
