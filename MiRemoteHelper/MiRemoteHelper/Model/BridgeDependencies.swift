import CoreBluetooth
import IOKit.hid

/// Hardware boundaries keep recovery tests independent of Bluetooth, audio and TCC.
protocol RemoteAudioRouting: AnyObject {
    var isReady: Bool { get }
    var isDeviceAlive: Bool { get }
    var deviceUID: String { get }
    var queuedFrames: Int { get }
    var error: String? { get }
    func configure(uid: String) -> Bool
    func beginSession()
    func stop()
    func enqueue(_ samples: [Int16], completion: (() -> Void)?) -> Bool
    func testTone(completion: @escaping () -> Void) -> Bool
    func whenDrained(_ completion: @escaping () -> Void)
}
extension RemoteAudioOutput: RemoteAudioRouting {}

protocol VoiceKeyMapping: AnyObject {
    var error: String? { get }
    func apply(_ key: VoiceKey) -> Bool
    func restore() -> Bool
}
extension VoiceKeyMapper: VoiceKeyMapping {}

protocol RemoteVoiceTransport: AnyObject {
    func start()
    func stop()
    func reconnectNow()
    func setVoiceBridgingEnabled(_ enabled: Bool)
}
extension XiaomiBluetoothBridge: RemoteVoiceTransport {}

struct BridgePermissions {
    var inputMonitoring: Bool
    var accessibility: Bool
    var bluetooth: Bool
    static func current() -> Self {
        Self(inputMonitoring: IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted,
             accessibility: VoiceToggleShortcut.isTrusted,
             bluetooth: CBManager.authorization == .allowedAlways)
    }
}
