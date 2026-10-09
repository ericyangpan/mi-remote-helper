import CoreGraphics
import Foundation
import OSLog

/// Debug-only metadata for the voice key. Never records text or audio.
final class VoiceEventDiagnostics {
    static let marker: Int64 = 0x4D52_5643
    #if DEBUG
    private static let enabled = ProcessInfo.processInfo.environment["MI_REMOTE_VOICE_DIAGNOSTICS"] == "1"
    private static let logger = Logger(subsystem: "com.yangpan.MiRemoteHelper", category: "voice-events")
    #endif
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    static func record(_ message: @autoclosure () -> String) {
        #if DEBUG
        guard enabled else { return }
        let metadata = message()
        logger.info("\(metadata, privacy: .private)")
        #endif
    }

    func start() {
        #if DEBUG
        guard Self.enabled, tap == nil else { return }
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
                                         options: .listenOnly, eventsOfInterest: CGEventMask(mask),
                                         callback: { _, type, event, _ in
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            if (type == .flagsChanged || type == .keyDown || type == .keyUp), [59, 62, 63, 96].contains(code) {
                VoiceEventDiagnostics.record("OBSERVE type=\(type.rawValue) key=\(code) flags=\(String(event.flags.rawValue, radix: 16)) ours=\(event.getIntegerValueField(.eventSourceUserData) == VoiceEventDiagnostics.marker)")
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: nil) else {
            VoiceEventDiagnostics.record("OBSERVER unavailable")
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        VoiceEventDiagnostics.record("OBSERVER started")
        #endif
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
    }
}
