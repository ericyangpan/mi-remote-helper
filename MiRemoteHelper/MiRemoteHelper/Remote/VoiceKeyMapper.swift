// SPDX-License-Identifier: GPL-3.0-only
// Device mapping approach adapted from Open Voice Bridge. See THIRD_PARTY_NOTICES.md.
import Foundation
import IOKit.hid
import IOKit.hidsystem

struct KeyMapping: Equatable {
    static let sourceKey = "HIDKeyboardModifierMappingSrc"
    static let destinationKey = "HIDKeyboardModifierMappingDst"
    static let microphone: UInt64 = 0x0000_0007_0000_003E
    let source: UInt64
    let destination: UInt64
    var dictionary: [String: NSNumber] {
        [Self.sourceKey: NSNumber(value: source), Self.destinationKey: NSNumber(value: destination)]
    }
    static func equivalent(_ lhs: [KeyMapping], _ rhs: [KeyMapping]) -> Bool {
        func ordered(_ values: [KeyMapping]) -> [KeyMapping] {
            values.sorted { $0.source == $1.source ? $0.destination < $1.destination : $0.source < $1.source }
        }
        return ordered(lhs) == ordered(rhs)
    }
    /// Already-correct mappings require no write. HID can reorder the array or
    /// return false after accepting a property; verify the resulting state.
    static func update(current: [KeyMapping], desired: [KeyMapping],
                       write: ([KeyMapping]) -> Bool, read: () -> [KeyMapping]) -> Bool {
        if equivalent(current, desired) { return true }
        _ = write(desired)
        return equivalent(read(), desired)
    }
    static func applying(_ destinations: [UInt64: UInt64], to current: [KeyMapping]) -> [KeyMapping] {
        current.filter { destinations[$0.source] == nil } + destinations.sorted { $0.key < $1.key }.map {
            KeyMapping(source: $0.key, destination: $0.value)
        }
    }
    static func restoring(_ current: [KeyMapping], originals: [UInt64: UInt64], installed: [UInt64: UInt64]) -> [KeyMapping] {
        var result = current
        for source in installed.keys.sorted() {
            guard current.first(where: { $0.source == source })?.destination == installed[source] else { continue }
            result.removeAll { $0.source == source }
            if let original = originals[source] { result.append(KeyMapping(source: source, destination: original)) }
        }
        return result
    }
    static func replacingVoice(in current: [KeyMapping], with destination: UInt64?) -> [KeyMapping] {
        current.filter { $0.source != microphone } + (destination.map { [KeyMapping(source: microphone, destination: $0)] } ?? [])
    }
}

final class VoiceKeyMapper {
    // Service clients depend on their event-system connection. Retaining only the
    // returned services is insufficient: keep their owner alive through every
    // property read, mapping write and restoration.
    private var client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)

    private struct Snapshot {
        let original: UInt64?
        var installed: UInt64
    }
    private var snapshots: [UInt64: [UInt64: Snapshot]] = [:]
    private let property = "UserKeyMapping" as CFString
    private(set) var error: String?

    // IOHID service properties affect this device only. They are not global keyboard mappings.
    func apply(_ key: VoiceKey) -> Bool {
        // Toggle shortcuts use separate start/end taps from ATVV. Disable
        // this remote's native F5 path so the input method cannot receive both.
        let destination = key.nativeMappingDestination
        let applied = apply(destinations: [KeyMapping.microphone: destination])
        if !applied {
            // Rebuild after all service operations finish. A retained client can
            // become stale across HID reconnects; snapshots still own restoration.
            client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        }
        return applied
    }

    func suppressOrdinaryButtons() -> Bool {
        apply(destinations: Dictionary(uniqueKeysWithValues: RemoteButton.allCases.filter { $0 != .microphone }.map {
            (UInt64(0x0000_0007_0000_0000) | UInt64($0.hidUsage), UInt64(0))
        }))
    }

    private func apply(destinations: [UInt64: UInt64]) -> Bool {
        let services = targets()
        guard !services.isEmpty else { error = String.appStatus("Remote keyboard connection not found. Check that the remote is paired in Bluetooth settings."); return false }
        for service in services {
            guard let id = registryID(service) else { error = String.appStatus("Unable to identify the remote keyboard connection."); return false }
            let current = read(service)
            for (source, destination) in destinations {
                let existing = current.first { $0.source == source }?.destination
                if let saved = snapshots[id]?[source], existing != saved.installed {
                    error = String.appStatus("Another tool changed the voice key mapping. Close other remote helper apps first.")
                    return false
                }
                if snapshots[id]?[source] == nil {
                    snapshots[id, default: [:]][source] = Snapshot(original: existing, installed: destination)
                }
            }
            let desired = KeyMapping.applying(destinations, to: current)
            guard KeyMapping.update(current: current, desired: desired,
                                    write: { self.write($0, to: service) }, read: { self.read(service) }) else {
                error = String.appStatus("Unable to configure the voice key. Allow Input Monitoring and try again.")
                _ = restore()
                return false
            }
            for (source, destination) in destinations { snapshots[id]?[source]?.installed = destination }
        }
        error = nil
        return true
    }

    @discardableResult func restore() -> Bool {
        let services = targets()
        var failed = false
        let present = Set(services.compactMap(registryID))
        snapshots = snapshots.filter { present.contains($0.key) }
        for service in services {
            guard let id = registryID(service), let saved = snapshots[id] else { continue }
            let current = read(service)
            let desired = KeyMapping.restoring(current,
                originals: saved.compactMapValues(\.original), installed: saved.mapValues(\.installed))
            if KeyMapping.update(current: current, desired: desired,
                                 write: { self.write($0, to: service) }, read: { self.read(service) }) { snapshots.removeValue(forKey: id) }
            else { failed = true }
        }
        if failed {
            error = String.appStatus("Unable to restore the original voice key mapping. Disconnect and reconnect the remote.")
            client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        }
        return !failed
    }

    private func targets() -> [IOHIDServiceClient] {
        return (IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] ?? []).filter {
            (IOHIDServiceClientCopyProperty($0, kIOHIDVendorIDKey as CFString) as? NSNumber)?.intValue == 0x2717 &&
            (IOHIDServiceClientCopyProperty($0, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue == 0x32B8
        }
    }

    // Read-only diagnostic used to exercise service access without modifying keys.
    func currentMappings() -> [UInt64: [KeyMapping]] {
        var result: [UInt64: [KeyMapping]] = [:]
        for service in targets() {
            guard let id = registryID(service) else { continue }
            result[id] = read(service)
        }
        return result
    }
    private func registryID(_ service: IOHIDServiceClient) -> UInt64? {
        (IOHIDServiceClientGetRegistryID(service) as? NSNumber)?.uint64Value
    }
    private func read(_ service: IOHIDServiceClient) -> [KeyMapping] {
        let values = IOHIDServiceClientCopyProperty(service, property) as? [[String: NSNumber]] ?? []
        return values.compactMap {
            guard let src = $0[KeyMapping.sourceKey], let dst = $0[KeyMapping.destinationKey] else { return nil }
            return KeyMapping(source: src.uint64Value, destination: dst.uint64Value)
        }
    }
    private func write(_ values: [KeyMapping], to service: IOHIDServiceClient) -> Bool {
        IOHIDServiceClientSetProperty(service, property, values.map(\.dictionary) as CFArray)
    }
}
