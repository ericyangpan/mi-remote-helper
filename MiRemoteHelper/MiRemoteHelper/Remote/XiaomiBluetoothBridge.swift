// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Open Voice Bridge, Copyright (C) 2026 Open Voice Bridge contributors.
// Reference: 1796b149f752ff2d2fa82fd818f8a5a2bc60802a. See THIRD_PARTY_NOTICES.md.

import CoreBluetooth
import Foundation

enum BluetoothBridgeState: Equatable {
    case stopped
    case initializingBluetooth
    case awaitingBluetoothPermission
    case bluetoothUnavailable(String)
    case scanning
    case connecting
    case discovering
    case ready(String)
    case reconnecting
    case failed(String)

    var displayText: String {
        switch self {
        case .stopped: return String.appStatus("Stopped")
        case .initializingBluetooth: return String.appStatus("Initializing Bluetooth")
        case .awaitingBluetoothPermission: return String.appStatus("Waiting for Bluetooth Permission")
        case .bluetoothUnavailable(let reason): return reason
        case .scanning: return String.appStatus("Searching for MI RC")
        case .connecting: return String.appStatus("Connecting to Remote")
        case .discovering: return String.appStatus("Initializing Voice Service")
        case .ready(let name): return String.appStatus("Connected to \(name)")
        case .reconnecting: return String.appStatus("Disconnected, Reconnecting")
        case .failed(let reason): return reason
        }
    }

    static func initialState(authorization: CBManagerAuthorization) -> Self {
        switch authorization {
        case .allowedAlways: return .initializingBluetooth
        case .notDetermined: return .awaitingBluetoothPermission
        case .denied: return .bluetoothUnavailable(String.appStatus("Bluetooth permission not granted"))
        case .restricted: return .bluetoothUnavailable(String.appStatus("Bluetooth access restricted by the system"))
        @unknown default: return .bluetoothUnavailable(String.appStatus("Bluetooth permission status unavailable"))
        }
    }
}

protocol XiaomiBluetoothBridgeDelegate: AnyObject {
    func bluetoothBridge(_ bridge: XiaomiBluetoothBridge, didChange state: BluetoothBridgeState)
    func bluetoothBridge(_ bridge: XiaomiBluetoothBridge, didDetectModelNumber modelNumber: String)
    func bluetoothBridge(_ bridge: XiaomiBluetoothBridge, didUpdateBatteryLevel level: RemoteBatteryLevel?)
    func bluetoothBridge(_ bridge: XiaomiBluetoothBridge, didUpdateCharging charging: Bool?)
    func bluetoothBridgeDidStartVoice(_ bridge: XiaomiBluetoothBridge)
    func bluetoothBridgeDidStopVoice(_ bridge: XiaomiBluetoothBridge)
    func bluetoothBridge(
        _ bridge: XiaomiBluetoothBridge,
        didObserveVoiceKey edge: RemoteEventEdge
    )
    func bluetoothBridge(_ bridge: XiaomiBluetoothBridge, didDecode samples: [Int16])
}

private final class XiaomiPeripheralDelegateProxy: NSObject, CBPeripheralDelegate {
    let generation: UInt64
    weak var owner: XiaomiBluetoothBridge?

    init(generation: UInt64, owner: XiaomiBluetoothBridge) {
        self.generation = generation
        self.owner = owner
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        owner?.handleDiscoveredServices(
            peripheral: peripheral,
            generation: generation,
            error: error
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        owner?.handleDiscoveredCharacteristics(
            peripheral: peripheral,
            generation: generation,
            service: service,
            error: error
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        owner?.handleNotificationState(
            peripheral: peripheral,
            generation: generation,
            characteristic: characteristic,
            error: error
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        owner?.handleCharacteristicValue(
            peripheral: peripheral,
            generation: generation,
            characteristic: characteristic,
            error: error
        )
    }
}

final class XiaomiBluetoothBridge: NSObject {
    private static let defaultCapabilities = ATVVCapabilities(
        version: 0x0100,
        codecs: 0x02,
        interaction: 0x03,
        frameSize: 120,
        selectedCodec: 0x02,
        sampleRate: 16_000
    )

    private let settings: AppSettings
    private weak var delegate: XiaomiBluetoothBridgeDelegate?
    private var central: CBCentralManager?
    private var centralGeneration: UInt64?
    private var peripheral: CBPeripheral?
    private var peripheralDelegateProxy: XiaomiPeripheralDelegateProxy?
    private var transmitCharacteristic: CBCharacteristic?
    private var audioCharacteristic: CBCharacteristic?
    private var controlCharacteristic: CBCharacteristic?
    private var modelNumberCharacteristic: CBCharacteristic?
    private var subscribedUUIDs = Set<CBUUID>()
    private var reconnectWorkItem: DispatchWorkItem?
    private var initializationTimeoutWorkItem: DispatchWorkItem?
    private var capabilitiesRequested = false
    private var capabilitiesConfirmed = false
    private var modelConfirmation = XiaomiModelConfirmationGate()
    private var requestedReconnectDelay: TimeInterval?
    private var generationCounter: UInt64 = 0
    private var lifecycle: BluetoothLifecyclePhase = .stopped
    private var shouldRun = false
    private var capabilities = XiaomiBluetoothBridge.defaultCapabilities
    private var decoder = IMAADPCMDecoder()
    private var accumulator = FrameAccumulator()
    private var pendingSync: (predictor: Int, stepIndex: Int)?
    private var streaming = false
    private var microphoneOpened = false
    private var sessionID: UInt8 = 0
    private var voiceControlEdgeTracker = RemoteVoiceControlEdgeTracker()
    /// Runtime voice gate. When false (bridge runtime disabled) the BLE link and
    /// its state observation stay live, but the remote must not open the
    /// microphone, start/continue a stream, or push audio. Independent of the BLE
    /// connection lifecycle.
    private var voiceBridgingEnabled = true

    private let serviceUUID = CBUUID(string: ATVVProtocol.serviceUUID)
    private let transmitUUID = CBUUID(string: ATVVProtocol.transmitUUID)
    private let audioUUID = CBUUID(string: ATVVProtocol.audioUUID)
    private let controlUUID = CBUUID(string: ATVVProtocol.controlUUID)
    private let deviceInformationServiceUUID = CBUUID(string: "180A")
    private let modelNumberUUID = CBUUID(string: "2A24")
    private let batteryServiceUUID = CBUUID(string: "180F")
    private let batteryLevelUUID = CBUUID(string: "2A19")
    private let batteryStatusUUID = CBUUID(string: "2BED")
    private var batteryCharging: Bool? {
        didSet {
            guard oldValue != batteryCharging else { return }
            delegate?.bluetoothBridge(self, didUpdateCharging: batteryCharging)
        }
    }
    private var batteryLevel: RemoteBatteryLevel? {
        didSet {
            guard oldValue != batteryLevel else { return }
            delegate?.bluetoothBridge(self, didUpdateBatteryLevel: batteryLevel)
        }
    }

    private(set) var state: BluetoothBridgeState = .stopped {
        didSet {
            guard oldValue != state else { return }
            switch state {
            case .stopped, .reconnecting, .failed, .bluetoothUnavailable:
                batteryLevel = nil
                batteryCharging = nil
            default: break
            }
            delegate?.bluetoothBridge(self, didChange: state)
        }
    }

    init(settings: AppSettings, delegate: XiaomiBluetoothBridgeDelegate) {
        self.settings = settings
        self.delegate = delegate
        super.init()
    }

    func start() {
        shouldRun = true
        reconnectWorkItem?.cancel()
        if central != nil { reconnectNow() }
        else { beginConnectionCycle() }
    }

    func stop() {
        shouldRun = false
        reconnectWorkItem?.cancel()
        central?.stopScan()
        closeMicrophoneIfNeeded()
        if let central, let peripheral, peripheral.state != .disconnected {
            requestedReconnectDelay = nil
            lifecycle = .disconnecting(lifecycle.generation ?? generationCounter)
            central.cancelPeripheralConnection(peripheral)
        } else {
            finishAttempt(reconnectAfter: nil)
        }
        resetSession()
        state = .stopped
    }

    /// Enables/disables the voice bridging path without touching the BLE
    /// connection. Disabling immediately closes the microphone (if open), stops any
    /// active stream (which notifies the delegate so the Fn latch, arbiter, and
    /// audio output are cleaned up), and drops any partial decode state. The link
    /// stays connected so a re-enable is instant.
    func setVoiceBridgingEnabled(_ enabled: Bool) {
        guard enabled != voiceBridgingEnabled else { return }
        voiceBridgingEnabled = enabled
        if enabled {
            AppLogger.shared.write("ATVV VOICE_GATE enabled")
            return
        }
        // A manual bridge pause can happen after ATVV reported MIC_OPEN but
        // before the same press reports STREAM_START/STOP. Drain that press
        // instead of resetting to idle, or its delayed STREAM_START would look
        // like a new tap and could arm an accidental restore.
        voiceControlEdgeTracker.cancelCurrentPress()
        closeMicrophoneIfNeeded()
        if streaming {
            stopStreaming()
        } else {
            accumulator.reset()
            pendingSync = nil
            decoder.reset()
        }
        AppLogger.shared.write("ATVV VOICE_GATE disabled")
    }

    func reconnectNow() {
        guard shouldRun else { return }
        reconnectWorkItem?.cancel()
        central?.stopScan()
        if let central, let peripheral, peripheral.state != .disconnected {
            requestedReconnectDelay = 0.1
            lifecycle = .disconnecting(lifecycle.generation ?? generationCounter)
            state = .reconnecting
            central.cancelPeripheralConnection(peripheral)
            return
        }
        finishAttempt(reconnectAfter: 0.1)
    }

    private func beginConnectionCycle() {
        guard shouldRun, central == nil else { return }
        // CoreBluetooth can wait for TCC before delivering its first callback.
        // Show that wait immediately instead of leaving the UI at "stopped".
        state = .initialState(authorization: CBManager.authorization)
        generationCounter &+= 1
        let generation = generationCounter
        lifecycle = .scanning(generation)
        let manager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
        central = manager
        centralGeneration = generation
        if manager.state == .poweredOn {
            discoverOrScan(using: manager, generation: generation)
        }
    }

    private func discoverOrScan(using central: CBCentralManager, generation: UInt64) {
        guard shouldRun,
              self.central === central,
              lifecycle == .scanning(generation),
              central.state == .poweredOn
        else { return }
        resetPeripheral()

        if let identifier = settings.peripheralIdentifier,
           let saved = central.retrievePeripherals(withIdentifiers: [identifier]).first {
            connect(saved, using: central, generation: generation)
            return
        }

        if let connected = central.retrieveConnectedPeripherals(withServices: [serviceUUID])
            .first(where: isCandidate) {
            connect(connected, using: central, generation: generation)
            return
        }

        state = .scanning
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        AppLogger.shared.write("BLE SCANNING")
    }

    private func connect(
        _ candidate: CBPeripheral,
        using central: CBCentralManager,
        generation: UInt64
    ) {
        guard shouldRun,
              self.central === central,
              peripheral == nil,
              lifecycle == .scanning(generation)
        else { return }
        central.stopScan()
        peripheral = candidate
        let proxy = XiaomiPeripheralDelegateProxy(generation: generation, owner: self)
        peripheralDelegateProxy = proxy
        candidate.delegate = proxy
        lifecycle = .connecting(generation)
        state = .connecting
        startConnectionTimeout(generation: generation)
        central.connect(candidate, options: nil)
        AppLogger.shared.write("BLE CONNECTING name=\(candidate.name ?? "unknown")")
    }

    private func isCandidate(_ candidate: CBPeripheral) -> Bool {
        RC003NameMatcher.matches(candidate.name)
    }

    private func resetPeripheral() {
        batteryLevel = nil
        batteryCharging = nil
        peripheral?.delegate = nil
        peripheral = nil
        peripheralDelegateProxy = nil
        transmitCharacteristic = nil
        audioCharacteristic = nil
        controlCharacteristic = nil
        modelNumberCharacteristic = nil
        subscribedUUIDs.removeAll()
        initializationTimeoutWorkItem?.cancel()
        initializationTimeoutWorkItem = nil
        capabilitiesRequested = false
        capabilitiesConfirmed = false
        modelConfirmation.reset()
        capabilities = Self.defaultCapabilities
        resetSession()
    }

    private func isCurrent(_ candidate: CBPeripheral) -> Bool {
        guard let peripheral else { return false }
        return peripheral === candidate
    }

    private func currentGeneration() -> UInt64? {
        lifecycle.generation
    }

    private func startConnectionTimeout(generation: UInt64) {
        initializationTimeoutWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.lifecycle == .connecting(generation) else { return }
            self.settings.peripheralIdentifier = nil
            self.scheduleReconnect(discardCachedIdentity: true)
        }
        initializationTimeoutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: work)
    }

    private func startInitializationTimeout(generation: UInt64) {
        initializationTimeoutWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  self.shouldRun,
                  self.currentGeneration() == generation,
                  self.lifecycle == .discovering(generation) ||
                    self.lifecycle == .awaitingCapabilities(generation)
            else { return }
            self.failInitialization(String.appStatus("ATVV initialization timed out"))
        }
        initializationTimeoutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }

    private func resetSession() {
        if streaming {
            streaming = false
            delegate?.bluetoothBridgeDidStopVoice(self)
        }
        microphoneOpened = false
        sessionID = 0
        accumulator.reset()
        pendingSync = nil
        decoder.reset()
        voiceControlEdgeTracker.reset()
    }

    private func observeVoiceControl(active: Bool) {
        guard let edge = voiceControlEdgeTracker.update(active: active) else { return }
        delegate?.bluetoothBridge(self, didObserveVoiceKey: edge)
    }

    private func scheduleReconnect(discardCachedIdentity: Bool = false) {
        guard shouldRun else { return }
        reconnectWorkItem?.cancel()
        state = .reconnecting
        if discardCachedIdentity {
            settings.peripheralIdentifier = nil
        }
        if let central, let peripheral, peripheral.state != .disconnected {
            requestedReconnectDelay = 3
            lifecycle = .disconnecting(lifecycle.generation ?? generationCounter)
            central.cancelPeripheralConnection(peripheral)
            return
        }
        finishAttempt(reconnectAfter: 3)
    }

    private func finishAttempt(reconnectAfter delay: TimeInterval?) {
        let finishedGeneration = lifecycle.generation ?? generationCounter
        central?.stopScan()
        central?.delegate = nil
        central = nil
        centralGeneration = nil
        requestedReconnectDelay = nil
        resetPeripheral()

        guard shouldRun, let delay else {
            lifecycle = .stopped
            return
        }

        lifecycle = .waitingReconnect(finishedGeneration)
        state = .reconnecting
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  self.shouldRun,
                  self.central == nil,
                  self.lifecycle == .waitingReconnect(finishedGeneration)
            else { return }
            self.beginConnectionCycle()
        }
        reconnectWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func write(_ data: Data) {
        guard let peripheral, let transmitCharacteristic else { return }
        let type: CBCharacteristicWriteType = transmitCharacteristic.properties.contains(.writeWithoutResponse)
            ? .withoutResponse
            : .withResponse
        peripheral.writeValue(data, for: transmitCharacteristic, type: type)
    }

    private func closeMicrophoneIfNeeded() {
        guard microphoneOpened else { return }
        write(ATVVProtocol.microphoneClose(
            version: capabilities.version,
            sessionID: sessionID
        ))
        microphoneOpened = false
    }

    private func requestCapabilitiesIfPossible() {
        guard let generation = currentGeneration(),
              lifecycle.acceptsInitializationCallback(generation: generation)
        else { return }
        guard transmitCharacteristic != nil,
              let audioCharacteristic,
              let controlCharacteristic,
              subscribedUUIDs.contains(audioCharacteristic.uuid),
              subscribedUUIDs.contains(controlCharacteristic.uuid),
              let peripheral
        else { return }
        guard !capabilitiesRequested else { return }
        capabilitiesRequested = true
        write(ATVVProtocol.getCapabilitiesV10)
        lifecycle = .awaitingCapabilities(generation)
        state = .discovering
        AppLogger.shared.write("ATVV CAPABILITIES requested name=\(peripheral.name ?? "MI RC")")
    }

    private func completeInitializationIfPossible() {
        guard let generation = currentGeneration(),
              lifecycle.acceptsCapabilities(generation: generation),
              capabilitiesConfirmed,
              modelConfirmation.isConfirmed,
              let peripheral
        else { return }
        initializationTimeoutWorkItem?.cancel()
        initializationTimeoutWorkItem = nil
        lifecycle = .ready(generation)
        settings.peripheralIdentifier = peripheral.identifier
        state = .ready(peripheral.name ?? "MI RC")
        AppLogger.shared.write("BLE READY name=\(peripheral.name ?? "MI RC") model_confirmed=true")
    }

    private func handleControl(_ data: Data) {
        let bytes = Array(data)
        guard let opcode = bytes.first,
              let generation = currentGeneration()
        else { return }

        switch opcode {
        case 0x0B:
            guard lifecycle.acceptsCapabilities(generation: generation) else {
                AppLogger.shared.write("ATVV CAPS ignored_stale_phase")
                return
            }
            guard let parsed = ATVVCapabilities.parse(data) else {
                failInitialization(String.appStatus("The remote returned an invalid ATVV capability response"))
                return
            }
            capabilities = parsed
            AppLogger.shared.write(
                "ATVV CAPS version=\(parsed.version) codec=\(parsed.selectedCodec) frame=\(parsed.frameSize)"
            )
            if !ATVVProtocol.supportsAudio(sampleRate: parsed.sampleRate) {
                rejectUnsupportedAudio(String.appStatus("The remote does not support the required 16 kHz audio codec"))
                return
            }
            capabilitiesConfirmed = true
            completeInitializationIfPossible()
        case 0x08:
            guard lifecycle.acceptsProtocolData(generation: generation) else { return }
            observeVoiceControl(active: true)
            guard ATVVVoiceBridgeGate.allowsVoice(bridgingEnabled: voiceBridgingEnabled) else {
                AppLogger.shared.write("ATVV MIC_OPEN ignored_bridging_disabled")
                return
            }
            guard ATVVSessionGate.canOpenMicrophone(
                phase: lifecycle,
                generation: generation,
                capabilitiesConfirmed: capabilitiesConfirmed,
                sampleRate: capabilities.sampleRate
            ) else {
                AppLogger.shared.write("ATVV MIC_OPEN ignored_not_ready")
                return
            }
            write(ATVVProtocol.microphoneOpen(
                version: capabilities.version,
                codec: capabilities.selectedCodec
            ))
            microphoneOpened = true
            AppLogger.shared.write("ATVV MIC_OPEN request")
        case 0x04:
            guard lifecycle.acceptsProtocolData(generation: generation) else { return }
            observeVoiceControl(active: true)
            guard ATVVVoiceBridgeGate.allowsVoice(bridgingEnabled: voiceBridgingEnabled) else {
                AppLogger.shared.write("ATVV STREAM_START ignored_bridging_disabled")
                return
            }
            guard ATVVSessionGate.canOpenMicrophone(
                phase: lifecycle,
                generation: generation,
                capabilitiesConfirmed: capabilitiesConfirmed,
                sampleRate: capabilities.sampleRate
            ) else {
                AppLogger.shared.write("ATVV STREAM_START ignored_not_ready")
                return
            }
            if bytes.count >= 3 {
                let codec = bytes[2]
                capabilities = ATVVCapabilities(
                    version: capabilities.version,
                    codecs: capabilities.codecs,
                    interaction: bytes[1],
                    frameSize: capabilities.frameSize,
                    selectedCodec: codec,
                    sampleRate: codec == 0x02 ? 16_000 : 8_000
                )
            }
            guard ATVVProtocol.supportsAudio(sampleRate: capabilities.sampleRate) else {
                rejectUnsupportedAudio(String.appStatus("The remote switched to an unsupported 8 kHz audio codec"))
                return
            }
            sessionID = bytes.count >= 4 ? bytes[3] : 0
            startStreaming()
        case 0x00:
            guard lifecycle.acceptsProtocolData(generation: generation) else { return }
            observeVoiceControl(active: false)
            stopStreaming()
        case 0x0A:
            guard lifecycle.acceptsProtocolData(generation: generation) else { return }
            guard bytes.count >= 7 else { return }
            let predictorBits = UInt16(bytes[4]) << 8 | UInt16(bytes[5])
            let predictor = Int(Int16(bitPattern: predictorBits))
            pendingSync = (predictor, Int(bytes[6]))
            accumulator.reset()
        default:
            break
        }
    }

    private func startStreaming() {
        guard !streaming else { return }
        accumulator.reset()
        // Preserve AUDIO_SYNC received before AUDIO_START in this session.
        decoder.reset()
        streaming = true
        delegate?.bluetoothBridgeDidStartVoice(self)
        AppLogger.shared.write("ATVV STREAM START session=\(sessionID)")
    }

    private func stopStreaming() {
        guard streaming else { return }
        streaming = false
        accumulator.reset()
        pendingSync = nil
        delegate?.bluetoothBridgeDidStopVoice(self)
        AppLogger.shared.write("ATVV STREAM STOP session=\(sessionID)")
    }

    private func handleAudio(_ data: Data) {
        guard ATVVVoiceBridgeGate.allowsVoice(bridgingEnabled: voiceBridgingEnabled) else {
            AppLogger.shared.write("ATVV AUDIO ignored_bridging_disabled")
            return
        }
        guard let generation = currentGeneration(),
              ATVVSessionGate.canOpenMicrophone(
                phase: lifecycle,
                generation: generation,
                capabilitiesConfirmed: capabilitiesConfirmed,
                sampleRate: capabilities.sampleRate
              )
        else {
            AppLogger.shared.write("ATVV AUDIO ignored_not_ready")
            return
        }
        // Audio alone cannot establish a new voice-key session. Notifications
        // from separate characteristics can arrive out of order, including tail
        // packets after STOP. Wait for a fresh control edge rather than latching
        // a shortcut or disabling the bridge because of an orphan packet.
        guard voiceControlEdgeTracker.isDown else { return }
        if !streaming {
            startStreaming()
            AppLogger.shared.write("ATVV STREAM implicit_audio_race")
        }

        // Starting the stream calls the delegate, which may reject/reconnect it.
        guard streaming, voiceBridgingEnabled else { return }
        let frames = accumulator.append(data, frameSize: capabilities.frameSize)
        for frame in frames {
            if let pendingSync {
                decoder.reset(
                    predictor: pendingSync.predictor,
                    stepIndex: pendingSync.stepIndex
                )
                self.pendingSync = nil
            }
            let decoded = decoder.decode(frame)
            let samples = PCMPostprocessor.process(decoded, gainDB: settings.activeGainDB, smoothing: !settings.whisperMode)
            delegate?.bluetoothBridge(self, didDecode: samples)
        }
    }

    private func rejectUnsupportedAudio(_ message: String) {
        state = .failed(message)
        closeMicrophoneIfNeeded()
        if streaming {
            stopStreaming()
        } else {
            accumulator.reset()
            pendingSync = nil
            decoder.reset()
        }
        scheduleReconnect(discardCachedIdentity: true)
    }

    private func failInitialization(_ message: String) {
        state = .failed(message)
        accumulator.reset()
        pendingSync = nil
        decoder.reset()
        scheduleReconnect(discardCachedIdentity: true)
    }
}

extension XiaomiBluetoothBridge: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard self.central === central, let generation = centralGeneration else { return }
        switch central.state {
        case .poweredOn:
            if shouldRun { discoverOrScan(using: central, generation: generation) }
        case .poweredOff:
            resetPeripheral()
            lifecycle = .scanning(generation)
            state = .bluetoothUnavailable(String.appStatus("Bluetooth is off"))
        case .unauthorized:
            resetSession()
            state = .bluetoothUnavailable(String.appStatus("Bluetooth permission not granted"))
        case .unsupported:
            state = .bluetoothUnavailable(String.appStatus("This Mac does not support Bluetooth Low Energy"))
        case .resetting:
            resetPeripheral()
            lifecycle = .scanning(generation)
            state = .bluetoothUnavailable(String.appStatus("Bluetooth is resetting"))
        case .unknown:
            state = .initialState(authorization: CBManager.authorization)
        @unknown default:
            state = .bluetoothUnavailable(String.appStatus("Bluetooth status unavailable"))
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard self.central === central else { return }
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let serviceMatch = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?
            .contains(serviceUUID) == true
        guard let generation = centralGeneration,
              lifecycle == .scanning(generation),
              self.peripheral == nil,
              serviceMatch || isCandidate(peripheral) || RC003NameMatcher.matches(advertisedName)
        else { return }
        connect(peripheral, using: central, generation: generation)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard self.central === central else { return }
        guard shouldRun else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        guard isCurrent(peripheral),
              let generation = centralGeneration,
              lifecycle.acceptsDidConnect(generation: generation)
        else { return }
        lifecycle = .discovering(generation)
        state = .discovering
        startInitializationTimeout(generation: generation)
        peripheral.discoverServices([serviceUUID, deviceInformationServiceUUID, batteryServiceUUID])
        AppLogger.shared.write("BLE CONNECTED name=\(peripheral.name ?? "unknown")")
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        guard self.central === central,
              isCurrent(peripheral),
              let generation = centralGeneration,
              lifecycle.acceptsDidFailToConnect(generation: generation)
        else { return }
        AppLogger.shared.write("BLE CONNECT FAILED error=\(error?.localizedDescription ?? "unknown")")
        settings.peripheralIdentifier = nil
        let delay = shouldRun ? (requestedReconnectDelay ?? 3) : nil
        finishAttempt(reconnectAfter: delay)
        if !shouldRun { state = .stopped }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        guard self.central === central,
              isCurrent(peripheral),
              let generation = centralGeneration,
              lifecycle.acceptsDisconnect(generation: generation)
        else { return }
        handleDisconnect(error: error)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        timestamp: CFAbsoluteTime,
        isReconnecting: Bool,
        error: Error?
    ) {
        guard self.central === central,
              isCurrent(peripheral),
              let generation = centralGeneration,
              lifecycle.acceptsDisconnect(generation: generation)
        else { return }
        handleDisconnect(error: error)
    }

    private func handleDisconnect(error: Error?) {
        AppLogger.shared.write("BLE DISCONNECTED error=\(error?.localizedDescription ?? "none")")
        let delay = shouldRun ? (requestedReconnectDelay ?? 3) : nil
        finishAttempt(reconnectAfter: delay)
        if !shouldRun { state = .stopped }
    }
}

extension XiaomiBluetoothBridge {
    fileprivate func handleDiscoveredServices(
        peripheral: CBPeripheral,
        generation: UInt64,
        error: Error?
    ) {
        guard shouldRun,
              isCurrent(peripheral),
              currentGeneration() == generation,
              lifecycle.acceptsInitializationCallback(generation: generation)
        else { return }
        if let error {
            state = .failed(String.appStatus("Unable to discover the voice service: \(error.localizedDescription)"))
            scheduleReconnect(discardCachedIdentity: true)
            return
        }
        guard let deviceInformationService = peripheral.services?.first(
            where: { $0.uuid == deviceInformationServiceUUID }
        ) else {
            failInitialization(String.appStatus("The remote did not provide verifiable model information"))
            return
        }
        peripheral.discoverCharacteristics([modelNumberUUID], for: deviceInformationService)
        if let batteryService = peripheral.services?.first(where: { $0.uuid == batteryServiceUUID }) {
            peripheral.discoverCharacteristics([batteryLevelUUID, batteryStatusUUID], for: batteryService)
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            state = .failed(String.appStatus("The remote does not provide an ATVV voice service"))
            scheduleReconnect(discardCachedIdentity: true)
            return
        }
        peripheral.discoverCharacteristics(
            [transmitUUID, audioUUID, controlUUID],
            for: service
        )
    }

    fileprivate func handleDiscoveredCharacteristics(
        peripheral: CBPeripheral,
        generation: UInt64,
        service: CBService,
        error: Error?
    ) {
        guard shouldRun,
              isCurrent(peripheral),
              currentGeneration() == generation
        else { return }
        if service.uuid == batteryServiceUUID {
            guard lifecycle.acceptsNotificationUpdate(generation: generation), error == nil else { return }
            for characteristic in service.characteristics ?? []
                where characteristic.uuid == batteryLevelUUID || characteristic.uuid == batteryStatusUUID {
                if characteristic.properties.contains(.read) { peripheral.readValue(for: characteristic) }
                if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
            return
        }
        if service.uuid == deviceInformationServiceUUID {
            guard lifecycle.acceptsModelDiscovery(generation: generation) else { return }
            if let error {
                failInitialization(String.appStatus("Unable to read the remote model: \(error.localizedDescription)"))
                return
            }
            guard let characteristic = service.characteristics?.first(
                where: { $0.uuid == modelNumberUUID }
            ) else {
                failInitialization(String.appStatus("The remote did not provide a model number"))
                return
            }
            modelNumberCharacteristic = characteristic
            peripheral.readValue(for: characteristic)
            return
        }
        guard lifecycle.acceptsInitializationCallback(generation: generation) else { return }
        if let error {
            state = .failed(String.appStatus("Unable to discover voice channels: \(error.localizedDescription)"))
            scheduleReconnect(discardCachedIdentity: true)
            return
        }
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case transmitUUID:
                transmitCharacteristic = characteristic
            case audioUUID:
                audioCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            case controlUUID:
                controlCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            default:
                continue
            }
        }
        guard transmitCharacteristic != nil,
              audioCharacteristic != nil,
              controlCharacteristic != nil
        else {
            state = .failed(String.appStatus("ATVV channels are incomplete"))
            scheduleReconnect(discardCachedIdentity: true)
            return
        }
        requestCapabilitiesIfPossible()
    }

    fileprivate func handleNotificationState(
        peripheral: CBPeripheral,
        generation: UInt64,
        characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard shouldRun,
              isCurrent(peripheral),
              currentGeneration() == generation,
              lifecycle.acceptsNotificationUpdate(generation: generation)
        else { return }
        // Battery notifications are optional and must never fail the voice link.
        if characteristic.uuid == batteryLevelUUID || characteristic.uuid == batteryStatusUUID { return }
        if let error {
            state = .failed(String.appStatus("Unable to subscribe to voice channels: \(error.localizedDescription)"))
            scheduleReconnect(discardCachedIdentity: true)
            return
        }
        guard characteristic.uuid == audioUUID || characteristic.uuid == controlUUID else {
            return
        }
        guard characteristic.isNotifying else {
            subscribedUUIDs.remove(characteristic.uuid)
            failInitialization(String.appStatus("ATVV notifications are not active"))
            return
        }
        subscribedUUIDs.insert(characteristic.uuid)
        requestCapabilitiesIfPossible()
    }

    fileprivate func handleCharacteristicValue(
        peripheral: CBPeripheral,
        generation: UInt64,
        characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard shouldRun,
              isCurrent(peripheral),
              currentGeneration() == generation
        else { return }
        if characteristic.uuid == batteryStatusUUID {
            guard lifecycle.acceptsNotificationUpdate(generation: generation) else { return }
            let status = error == nil ? characteristic.value.flatMap(RemoteBatteryStatus.init(data:)) : nil
            batteryCharging = status?.isCharging
            if let percentage = status?.percentage {
                batteryLevel = RemoteBatteryLevel(data: Data([UInt8(percentage)]))
            }
            return
        }
        if characteristic.uuid == batteryLevelUUID {
            guard lifecycle.acceptsNotificationUpdate(generation: generation) else { return }
            batteryLevel = error == nil ? characteristic.value.flatMap(RemoteBatteryLevel.init(data:)) : nil
            return
        }
        if characteristic.uuid == modelNumberUUID {
            guard lifecycle.acceptsModelValue(generation: generation) else {
                AppLogger.shared.write("BLE MODEL ignored_stale_phase")
                return
            }
            if let error {
                failInitialization(String.appStatus("Unable to read the remote model: \(error.localizedDescription)"))
                return
            }
            guard let data = characteristic.value else {
                failInitialization(String.appStatus("The remote model number is empty"))
                return
            }
            let modelNumber = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines))
            guard let modelNumber, !modelNumber.isEmpty else {
                failInitialization(String.appStatus("The remote model number is unreadable"))
                return
            }
            guard XiaomiRemoteVariant.detected(fromModelNumber: modelNumber) != nil else {
                AppLogger.shared.write("BLE MODEL unsupported=\(modelNumber)")
                failInitialization(String.appStatus("Remote model \(modelNumber) is not supported"))
                return
            }
            guard modelConfirmation.accept(modelNumber) != nil else {
                AppLogger.shared.write(
                    "BLE MODEL ignored_duplicate_or_conflict=\(modelNumber) " +
                        "confirmed=\(modelConfirmation.modelNumber ?? "unknown")"
                )
                return
            }
            let confirmedModelNumber = modelConfirmation.modelNumber ?? modelNumber
            AppLogger.shared.write("BLE MODEL detected=\(confirmedModelNumber)")
            delegate?.bluetoothBridge(self, didDetectModelNumber: confirmedModelNumber)
            completeInitializationIfPossible()
        } else if characteristic.uuid == controlUUID {
            guard error == nil, let data = characteristic.value else { return }
            guard lifecycle.acceptsCapabilities(generation: generation) ||
                    lifecycle.acceptsProtocolData(generation: generation)
            else { return }
            handleControl(data)
        } else if characteristic.uuid == audioUUID {
            guard error == nil, let data = characteristic.value else { return }
            guard lifecycle.acceptsProtocolData(generation: generation) else { return }
            handleAudio(data)
        }
    }
}
