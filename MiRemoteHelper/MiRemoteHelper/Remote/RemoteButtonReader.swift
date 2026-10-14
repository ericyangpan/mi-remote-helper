import Foundation
import IOKit.hid

/// Reads only the RC003. If Bluetooth HID refuses exclusive access, suppress
/// its native button usages through device-local UserKeyMapping instead.
protocol RemoteButtonReading: AnyObject {
    var onActive: ((Bool, String?) -> Void)? { get set }
    var onReport: ((Set<UInt16>) -> Void)? { get set }
    var restorationPending: Bool { get }
    func start()
    @discardableResult func stop() -> Bool
}

final class RemoteButtonReader: RemoteButtonReading {
    var onActive: ((Bool, String?) -> Void)?
    var onReport: ((Set<UInt16>) -> Void)?
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var generation: UInt64 = 0
    private let nativeKeys = VoiceKeyMapper()
    private(set) var restorationPending = false

    func start() {
        guard manager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        self.manager = manager
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x2717, kIOHIDProductIDKey: 0x32B8] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, _, device in
            guard let context else { return }
            Unmanaged<RemoteButtonReader>.fromOpaque(context).takeUnretainedValue().matched(device, result: result)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<RemoteButtonReader>.fromOpaque(context).takeUnretainedValue().removed(device)
        }, context)
        IOHIDManagerRegisterInputReportCallback(manager, { context, result, sender, type, reportID, bytes, length in
            guard let context, result == kIOReturnSuccess, type == kIOHIDReportTypeInput, length > 0 else { return }
            let reader = Unmanaged<RemoteButtonReader>.fromOpaque(context).takeUnretainedValue()
            guard let device = reader.device, let sender,
                  sender == Unmanaged.passUnretained(device).toOpaque() else { return }
            let generation = reader.generation
            let data = Data(bytes: bytes, count: length)
            DispatchQueue.main.async { [weak reader] in
                guard let reader, reader.device != nil, reader.generation == generation,
                      let usages = RemoteHIDReportParser.usages(reportID: reportID, data: data) else { return }
                reader.onReport?(usages)
            }
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(manager, 0)
        if result != kIOReturnSuccess {
            AppLogger.shared.write("HID manager open failed: \(result)")
            stop()
            onActive?(false, String.appStatus("Unable to read the remote. Check Input Monitoring permission and reconnect."))
        } else if device == nil { onActive?(false, nil) }
    }

    @discardableResult func stop() -> Bool {
        generation &+= 1
        restorationPending = !nativeKeys.restore()
        if let device { IOHIDDeviceClose(device, 0) }
        device = nil
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, 0)
        }
        manager = nil
        return !restorationPending
    }

    private func matched(_ device: IOHIDDevice, result: IOReturn) {
        guard manager != nil, self.device == nil else { return }
        guard result == kIOReturnSuccess else { return }
        let seized = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice)) == kIOReturnSuccess
        if !seized {
            guard IOHIDDeviceOpen(device, 0) == kIOReturnSuccess, nativeKeys.suppressOrdinaryButtons() else {
                IOHIDDeviceClose(device, 0)
                restorationPending = !nativeKeys.restore()
                onActive?(false, nativeKeys.error ?? String.appStatus("Unable to take control of the remote’s buttons. Close other remapping apps, then turn mapping off and on."))
                return
            }
        }
        generation &+= 1
        self.device = device
        onActive?(true, nil)
    }

    private func removed(_ device: IOHIDDevice) {
        guard let current = self.device, CFEqual(current, device) else { return }
        generation &+= 1
        restorationPending = !nativeKeys.restore()
        IOHIDDeviceClose(current, 0)
        self.device = nil
        onActive?(false, nil)
    }
}
