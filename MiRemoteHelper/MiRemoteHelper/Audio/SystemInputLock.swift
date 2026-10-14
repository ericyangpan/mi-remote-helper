import CoreAudio
import Foundation

protocol SystemInputRouting: AnyObject {
    var onChange: (() -> Void)? { get set }
    var restorationError: String? { get }
    @discardableResult func lock(to uid: String) -> Bool
    func unlock()
}

/// Owns the default input only for the lifetime of a connected remote.
final class SystemInputLock: SystemInputRouting {
    var onChange: (() -> Void)?
    private let read: () -> String?
    private let write: (String) -> Bool
    private let observe: (@escaping () -> Void) -> (() -> Void)
    private var cancelObservation: (() -> Void)?
    private var targetUID: String?
    private var previousUID: String?
    private(set) var restorationError: String?
    private var restoring = false
    private var retriesRemaining = 0
    private var generation: UInt64 = 0
    private var cancelRetry: (() -> Void)?
    private let scheduleRetry: (@escaping () -> Void) -> (() -> Void)

    init(read: @escaping () -> String? = CoreAudioDeviceCatalog.defaultInputDeviceUID,
         write: @escaping (String) -> Bool = CoreAudioDeviceCatalog.setDefaultInputDevice,
         observe: @escaping (@escaping () -> Void) -> (() -> Void) = SystemInputLock.observeHardware,
         scheduleRetry: @escaping (@escaping () -> Void) -> (() -> Void) = { action in
             let work = DispatchWorkItem(block: action)
             DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
             return { work.cancel() }
         }) {
        self.read = read
        self.write = write
        self.observe = observe
        self.scheduleRetry = scheduleRetry
    }

    @discardableResult func lock(to uid: String) -> Bool {
        guard !uid.isEmpty else { unlock(); return false }
        if targetUID == nil || restoring {
            // A reconnect must retain the original input while we still own the
            // failed restoration, but respect an intervening external choice.
            if !restoring { previousUID = read() }
            else if let current = read(), current != targetUID { previousUID = current }
            cancelRetry?()
            cancelRetry = nil
            generation &+= 1
            let token = generation
            restoring = false
            restorationError = nil
            targetUID = uid
            cancelObservation = observe { [weak self] in
                guard let self, self.generation == token, !self.restoring,
                      let target = self.targetUID else { return }
                _ = self.enforce(target)
                self.onChange?()
            }
        } else { targetUID = uid }
        return enforce(uid)
    }

    private func enforce(_ uid: String) -> Bool {
        if read() == uid { return true }
        return write(uid) && read() == uid
    }

    func unlock() {
        // Health checks with locking disabled must not restart the retry budget.
        guard !restoring else {
            if let current = read(), current != targetUID { clearRestoration() }
            return
        }
        cancelObservation?()
        cancelObservation = nil
        generation &+= 1
        restoring = true
        retriesRemaining = 3
        attemptRestoration()
    }

    private func attemptRestoration() {
        guard let target = targetUID, let previous = previousUID, target != previous else {
            clearRestoration()
            return
        }
        if let current = read() {
            guard current == target else { clearRestoration(); return }
            _ = write(previous)
            if read() == previous { clearRestoration(); return }
        }
        guard retriesRemaining > 0 else {
            restorationError = String.appStatus("Unable to restore the previous audio input. Select an input in Sound settings.")
            return
        }
        restorationError = String.appStatus("Restoring the previous audio input…")
        retriesRemaining -= 1
        let token = generation
        cancelRetry = scheduleRetry { [weak self] in
            guard let self, self.restoring, self.generation == token else { return }
            self.cancelRetry = nil
            self.attemptRestoration()
            self.onChange?()
        }
    }

    private func clearRestoration() {
        cancelRetry?()
        cancelRetry = nil
        targetUID = nil
        previousUID = nil
        restoring = false
        restorationError = nil
    }

    deinit {
        cancelObservation?()
        cancelRetry?()
        // Termination cannot wait for an asynchronous retry.
        if let target = targetUID, let previous = previousUID,
           target != previous, read() == target { _ = write(previous) }
    }

    private static func observeHardware(_ changed: @escaping () -> Void) -> () -> Void {
        let object = AudioObjectID(kAudioObjectSystemObject)
        var registered: [AudioObjectPropertySelector] = []
        var pending: DispatchWorkItem?
        var active = true
        let listener: AudioObjectPropertyListenerBlock = { _, _ in
            guard active else { return }
            pending?.cancel()
            let work = DispatchWorkItem { if active { changed() } }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
        }
        for selector in [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDefaultOutputDevice,
                         kAudioHardwarePropertyDevices] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            if AudioObjectAddPropertyListenerBlock(object, &address, .main, listener) == noErr {
                registered.append(selector)
            }
        }
        return {
            active = false
            pending?.cancel()
            for selector in registered {
                var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                         mElement: kAudioObjectPropertyElementMain)
                AudioObjectRemovePropertyListenerBlock(object, &address, .main, listener)
            }
        }
    }
}
