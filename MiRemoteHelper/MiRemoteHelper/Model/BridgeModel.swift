import AppKit
import Combine
import CoreBluetooth
import IOKit.hid

final class BridgeModel: ObservableObject, XiaomiBluetoothBridgeDelegate {
    let settings: AppSettings
    let buttons: ButtonMappingModel
    private var legacyVoiceRelease: CGEvent?
    @Published private(set) var state: BluetoothBridgeState = .stopped
    @Published private(set) var batteryLevel: RemoteBatteryLevel?
    @Published private(set) var outputs: [AudioDeviceInfo] = []
    @Published private(set) var isRunning = false
    @Published private(set) var isSpeaking = false
    @Published private(set) var audioReady = false
    @Published private(set) var keyReady = false
    @Published private(set) var activeVoiceKey: VoiceKey = .leftControl
    @Published private(set) var sampleCount = 0
    @Published private(set) var level = 0.0
    @Published private(set) var peakDBFS: Double?
    @Published private(set) var audioOverloaded = false
    private var audioMeter = AudioInputMeter()
    @Published private(set) var message = String(localized: "Select a virtual microphone, then connect the remote.")
    @Published private(set) var testToneActive = false
    @Published private(set) var testToneMessage: String?
    @Published private(set) var inputMonitoringAllowed = false
    @Published private(set) var accessibilityAllowed = false
    @Published private(set) var bluetoothAllowed = false
    @Published private(set) var isVoiceKeyHeld = false
    @Published private(set) var inputRestorationError: String?
    var statusMessage: String { inputRestorationError ?? message }
    private let inputRoute: any SystemInputRouting
    @Published private(set) var inputRouteReady = false
    private var audioRecoveryPending = false
    private var nextAudioRecoveryAt: TimeInterval = 0
    private let output: any RemoteAudioRouting
    private let mapper: any VoiceKeyMapping
    private let voiceToggle: VoiceToggleShortcut
    private let voiceDiagnostics = VoiceEventDiagnostics()
    private var releaseWorkItem: DispatchWorkItem?
    private let makeTransport: (AppSettings, XiaomiBluetoothBridgeDelegate) -> any RemoteVoiceTransport
    private lazy var remote = makeTransport(settings, self)
    private let readPermissions: () -> BridgePermissions
    private let listDevices: () -> [AudioDeviceInfo]
    private let uptime: () -> TimeInterval
    private var pendingSettingsApply = false
    private var testToneGeneration: UInt64 = 0
    private var testToneTimeout: DispatchWorkItem?
    private var healthTimer: Timer?
    private var voiceWatchdog = VoiceSessionWatchdog()
    private var lastMeterAt = Date.distantPast
    private var subscriptions = Set<AnyCancellable>()

    var ready: Bool { audioReady && keyReady && inputRouteReady && isConnected }
    var isConnected: Bool { if case .ready = state { return true }; return false }
    var audioSeconds: Double { Double(sampleCount) / 16_000 }
    var activeOutputUID: String { audioReady ? output.deviceUID : "" }

    init(settings: AppSettings = AppSettings(), buttons: ButtonMappingModel = ButtonMappingModel(),
         inputRoute: any SystemInputRouting = SystemInputLock(),
         output: any RemoteAudioRouting = RemoteAudioOutput(), mapper: any VoiceKeyMapping = VoiceKeyMapper(),
         voiceToggle: VoiceToggleShortcut = VoiceToggleShortcut(),
         readPermissions: @escaping () -> BridgePermissions = BridgePermissions.current,
         listDevices: @escaping () -> [AudioDeviceInfo] = CoreAudioDeviceCatalog.loopbackDevices,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         makeTransport: @escaping (AppSettings, XiaomiBluetoothBridgeDelegate) -> any RemoteVoiceTransport = {
             XiaomiBluetoothBridge(settings: $0, delegate: $1)
         }) {
        self.settings = settings
        self.buttons = buttons
        self.inputRoute = inputRoute
        self.output = output
        self.mapper = mapper
        self.voiceToggle = voiceToggle
        self.readPermissions = readPermissions
        self.listDevices = listDevices
        self.uptime = uptime
        self.makeTransport = makeTransport
        inputRoute.onChange = { [weak self] in
            self?.refreshInputRestorationError()
            self?.checkHealth()
        }
        buttons.canEdit = { [weak self] in
            guard let self else { return false }
            return !self.isSpeaking && !self.isVoiceKeyHeld && !self.testToneActive
        }
        buttons.onAvailabilityChange = { [weak self] in
            guard let self, self.isRunning, self.isConnected else { return }
            // Fn/Ctrl sessions are owned by ATVV, independently of HID availability.
            // Keep the shortcut and watchdog alive until the stream and tail finish.
            if !self.activeVoiceKey.usesToggle && (self.isSpeaking || self.isVoiceKeyHeld) {
                // Legacy held keys depend on HID; recover the entire session together.
                self.remote.reconnectNow()
            } else { self.applySettings() }
        }
        buttons.onVoiceMappingEdge = { [weak self] edge in self?.handleLegacyVoiceKey(edge) }
        refreshDevices()
        refreshPermissions()
        if !settings.outputUID.isEmpty { message = String(localized: "Connect the remote to start voice input.") }
        settings.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
    }

    func refreshPermissions() {
        let permissions = readPermissions()
        let input = permissions.inputMonitoring
        let accessibility = permissions.accessibility
        let bluetooth = permissions.bluetooth
        if inputMonitoringAllowed != input { inputMonitoringAllowed = input }
        if accessibilityAllowed != accessibility { accessibilityAllowed = accessibility }
        if bluetoothAllowed != bluetooth { bluetoothAllowed = bluetooth }
    }
    func requestAccessibility() { VoiceToggleShortcut.requestAccess(); refreshPermissions() }
    func requestInputMonitoring() {
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        if access == kIOHIDAccessTypeDenied,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        } else {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        refreshPermissions()
    }

    func refreshDevices() {
        let devices = listDevices()
        if outputs != devices { outputs = devices }
        if settings.outputUID.isEmpty, outputs.count == 1 { settings.outputUID = outputs[0].uid }
    }

    func start() {
        guard !isRunning else { return }
        refreshDevices()
        isRunning = true
        sampleCount = 0
        remote.setVoiceBridgingEnabled(false)
        message = String(localized: "Press a button to wake the remote and keep it paired in Bluetooth settings.")
        remote.start()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.checkHealth() }
        healthTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        healthTimer?.invalidate()
        healthTimer = nil
        isRunning = false
        inputRoute.unlock()
        refreshInputRestorationError()
        inputRouteReady = false
        audioRecoveryPending = false
        pendingSettingsApply = false
        buttons.refresh(connected: false)
        releaseLegacyVoiceKey()
        releaseVoiceShortcut()
        voiceToggle.finishPendingTaps()
        voiceDiagnostics.stop()
        remote.stop()
        output.stop()
        keyReady = false
        audioReady = false
        isSpeaking = false
        resetAudioMeter()
        cancelTestTone()
        let voiceRestored = mapper.restore()
        message = buttons.restorationError ?? (voiceRestored ? String(localized: "Stopped. The original voice key mapping has been restored.") : (mapper.error ?? String(localized: "Please reconnect the remote.")))
    }

    func reconnect() {
        guard isRunning else { start(); return }
        remote.reconnectNow()
    }

    func applySettings() {
        guard !isSpeaking, !isVoiceKeyHeld, !testToneActive else {
            pendingSettingsApply = isRunning && isConnected
            return
        }
        pendingSettingsApply = false
        testToneMessage = nil
        refreshDevices()
        guard isConnected, isRunning else { return }
        remote.setVoiceBridgingEnabled(false)
        keyReady = false
        guard updateSystemInputPolicy() else {
            audioOutputFailed(message: String(localized: "Restoring the virtual microphone as system input…"))
            scheduleAudioRecovery()
            return
        }
        guard mapper.restore() else { message = mapper.error ?? String(localized: "Unable to restore the voice key mapping."); return }
        refreshPermissions()
        if settings.voiceKey.usesToggle, !accessibilityAllowed {
            output.stop()
            audioReady = false
            message = String(localized: "Allow Accessibility, then click Apply Settings to enable WeChat voice start and stop shortcuts.")
            return
        }
        audioReady = output.configure(uid: settings.outputUID)
        guard audioReady else {
            message = output.error ?? String(localized: "The virtual microphone is not ready.")
            scheduleAudioRecovery()
            return
        }
        audioRecoveryPending = false
        keyReady = mapper.apply(buttons.active ? .leftControl : settings.voiceKey)
        if keyReady { voiceDiagnostics.start() }
        if keyReady { activeVoiceKey = settings.voiceKey }
        remote.setVoiceBridgingEnabled(keyReady)
        if keyReady {
            message = activeVoiceKey.usesToggle
                ? String(localized: "Set the selected shortcut to toggle dictation in WeChat. Hold the remote’s voice button to speak and release it to finish.")
                : String(localized: "Set the matching shortcut in your input method, then hold the remote’s voice button to speak.")
        } else { message = mapper.error ?? String(localized: "The voice key is not ready.") }
    }

    func playTestTone() {
        guard !isSpeaking, !isVoiceKeyHeld, !testToneActive else { return }
        if !output.isReady || output.deviceUID != settings.outputUID {
            if isConnected { applySettings() }
            else { audioReady = output.configure(uid: settings.outputUID) }
        }
        guard audioReady, output.isReady, output.deviceUID == settings.outputUID else {
            testToneMessage = output.error ?? String(localized: "The virtual microphone is not ready.")
            return
        }
        cancelTestTone()
        testToneActive = true
        testToneMessage = String(localized: "Sending a test tone to the virtual microphone. Check the input level in Sound settings.")
        let token = testToneGeneration
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.testToneActive, self.testToneGeneration == token else { return }
            let message = String(localized: "Test tone timed out. Apply settings and try again.")
            self.audioOutputFailed(message: message)
            self.testToneMessage = message
        }
        testToneTimeout = timeout
        // This also runs when testing without a Bluetooth connection/health timer.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: timeout)
        let queued = output.testTone { [weak self] in
            guard let self, self.testToneGeneration == token, self.testToneActive else { return }
            self.cancelTestTone()
            self.testToneMessage = String(localized: "Test tone sent. Check that the input level changed in Sound settings.")
        }
        if !queued {
            cancelTestTone()
            testToneMessage = output.error ?? String(localized: "Unable to play the test tone.")
        }
    }

    private func cancelTestTone() {
        testToneGeneration &+= 1
        testToneTimeout?.cancel()
        testToneTimeout = nil
        testToneActive = false
        testToneMessage = nil
    }

    private func audioOutputFailed(message: String) {
        pendingSettingsApply = false
        cancelTestTone()
        releaseVoiceShortcut()
        remote.setVoiceBridgingEnabled(false)
        output.stop()
        isSpeaking = false
        audioReady = false
        keyReady = false
        _ = mapper.restore()
        self.message = message
    }

    /// A disabled policy imposes no requirement on the system's input choice.
    @discardableResult private func updateSystemInputPolicy() -> Bool {
        let satisfied: Bool
        if settings.keepSystemInput { satisfied = inputRoute.lock(to: settings.outputUID) }
        else { inputRoute.unlock(); satisfied = true }
        refreshInputRestorationError()
        if inputRouteReady != satisfied { inputRouteReady = satisfied }
        return satisfied
    }

    private func refreshInputRestorationError() {
        if inputRestorationError != inputRoute.restorationError {
            inputRestorationError = inputRoute.restorationError
        }
    }

    private func scheduleAudioRecovery() {
        audioRecoveryPending = isRunning && isConnected
        nextAudioRecoveryAt = uptime() + 1
    }

    /// Rebuild only the output: an active Fn/Ctrl dictation session stays owned.
    @discardableResult private func recoverAudioOutput() -> Bool {
        cancelTestTone()
        if inputRouteReady, output.isDeviceAlive, output.configure(uid: settings.outputUID) {
            audioReady = true
            audioRecoveryPending = false
            return true
        }
        audioOutputFailed(message: String(localized: "Restoring the virtual microphone…"))
        scheduleAudioRecovery()
        return false
    }

    func checkHealth() {
        refreshPermissions()
        guard isRunning else { return }
        buttons.refresh(connected: isConnected)
        if isConnected {
            if !updateSystemInputPolicy() {
                if audioReady || isVoiceKeyHeld || testToneActive {
                    audioOutputFailed(message: String(localized: "Restoring the virtual microphone as system input…"))
                }
                if !audioRecoveryPending { scheduleAudioRecovery() }
                return
            }
        }
        if keyReady, activeVoiceKey.usesToggle, !accessibilityAllowed {
            releaseVoiceShortcut()
            remote.setVoiceBridgingEnabled(false)
            keyReady = false
            _ = mapper.restore()
            message = String(localized: "Accessibility access is unavailable. Grant permission, then apply settings again.")
        }
        if audioReady && (!output.isDeviceAlive || !output.isReady) {
            recoverAudioOutput()
        }
        if let failure = voiceWatchdog.failure(at: uptime()) {
            VoiceEventDiagnostics.record("VOICE timeout=\(failure)")
            voiceWatchdog.reset()
            message = String(localized: "Remote audio was interrupted. Reconnecting.")
            remote.reconnectNow()
        }
        if (pendingSettingsApply || (audioRecoveryPending && uptime() >= nextAudioRecoveryAt)),
           !isSpeaking, !isVoiceKeyHeld, !testToneActive { applySettings() }
    }

    func bluetoothBridge(_ bridge: XiaomiBluetoothBridge, didChange state: BluetoothBridgeState) {
        self.state = state
        refreshPermissions()
        buttons.refresh(connected: isConnected && isRunning)
        if case .ready = state { applySettings() }
        else {
            inputRoute.unlock()
            refreshInputRestorationError()
            inputRouteReady = false
            audioRecoveryPending = false
            pendingSettingsApply = false
            releaseLegacyVoiceKey()
            releaseVoiceShortcut()
            keyReady = false
            audioReady = false
            _ = mapper.restore()
            output.stop()
            isSpeaking = false
            cancelTestTone()
            resetAudioMeter()
            switch state {
            case .awaitingBluetoothPermission:
                message = String(localized: "Allow Bluetooth when prompted, or grant Mi Remote Helper access in Bluetooth privacy settings.")
            case .initializingBluetooth:
                message = String(localized: "Initializing Bluetooth. If it does not connect, check Bluetooth permission and try again.")
            case .bluetoothUnavailable(let reason):
                message = String(localized: "\(reason). Check Bluetooth and this app’s Bluetooth permission in System Settings.")
            case .scanning:
                message = String(localized: "Press a button to wake the remote and keep it paired in Bluetooth settings.")
            case .connecting, .discovering, .reconnecting:
                message = state.displayText + "…"
            case .failed(let reason): message = reason
            case .stopped, .ready: break
            }
        }
    }
    func bluetoothBridge(_ bridge: XiaomiBluetoothBridge, didDetectModelNumber modelNumber: String) {}

    func bluetoothBridge(_ bridge: XiaomiBluetoothBridge, didUpdateBatteryLevel level: RemoteBatteryLevel?) {
        batteryLevel = level
    }
    func bluetoothBridge(_ bridge: XiaomiBluetoothBridge, didObserveVoiceKey edge: RemoteEventEdge) {
        VoiceEventDiagnostics.record("ATVV edge=\(edge) ready=\(ready) held=\(voiceToggle.isHeld)")
        switch edge {
        case .down:
            // Do not run pending HID reconfiguration from inside an ATVV down
            // callback: disabling the voice gate here would cancel this new press.
            guard isRunning, isConnected else { return }
            guard updateSystemInputPolicy() else {
                audioOutputFailed(message: String(localized: "Restoring the virtual microphone as system input…"))
                scheduleAudioRecovery()
                return
            }
            if audioReady && (!output.isDeviceAlive || !output.isReady) { recoverAudioOutput() }
            guard ready else { return }
            let clearSwitcherCommand = buttons.prepareForVoiceInput()
            guard activeVoiceKey.usesToggle else {
                voiceWatchdog.press(at: uptime())
                return
            }
            // A new press must not inherit the previous session's delayed release.
            releaseVoiceShortcut()
            guard !voiceToggle.isHeld else { message = String(localized: "Unable to finish the previous voice shortcut. Stop and try again."); return }
            guard voiceToggle.press(key: activeVoiceKey, clearSwitcherCommand: clearSwitcherCommand) else {
                keyReady = false
                remote.setVoiceBridgingEnabled(false)
                message = String(localized: "Unable to send the voice shortcut. Check Accessibility permission.")
                return
            }
            isVoiceKeyHeld = true
            voiceWatchdog.press(at: uptime())
        case .up:
            voiceWatchdog.reset()
            finishVoiceShortcut()
        }
    }
    func bluetoothBridgeDidStartVoice(_ bridge: XiaomiBluetoothBridge) {
        VoiceEventDiagnostics.record("AUDIO start held=\(voiceToggle.isHeld)")
        guard ready else { return }
        if activeVoiceKey.usesToggle, !voiceToggle.isHeld {
            // Recover the transport instead of permanently disabling future presses.
            VoiceEventDiagnostics.record("VOICE unowned-stream reconnect")
            remote.reconnectNow()
            return
        }
        resetAudioMeter()
        output.beginSession()
        isSpeaking = true
        cancelTestTone()
        sampleCount = 0
        message = String(localized: "Receiving audio from the remote…")
    }
    func bluetoothBridgeDidStopVoice(_ bridge: XiaomiBluetoothBridge) {
        sampleCount = audioMeter.sampleCount
        voiceWatchdog.reset()
        VoiceEventDiagnostics.record("AUDIO stop queued=\(output.queuedFrames) held=\(voiceToggle.isHeld)")
        finishVoiceShortcut()
        isSpeaking = false
        level = 0
        peakDBFS = nil
        // Leave queued tail audio to finish playing. Starting another session flushes it.
        if isRunning { message = sampleCount > 0 ? String(format: String(localized: "Received %.1f seconds of audio. WeChat Input handles transcription."), locale: Locale.current, audioSeconds) : String(localized: "No audio received. Hold the voice button and try again.") }
    }

    private func finishVoiceShortcut() {
        guard voiceToggle.isHeld else { return }
        releaseWorkItem?.cancel()
        let generation = voiceToggle.generation
        let release = { [weak self] in
            guard let self, self.voiceToggle.generation == generation else { return }
            self.releaseVoiceShortcut(ifGeneration: generation)
        }
        // Let the final PCM reach BlackHole before ending WeChat capture. The
        // timeout also ends dictation if the output device stops consuming audio.
        let work = DispatchWorkItem(block: release)
        releaseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: work)
        output.whenDrained(release)
    }

    private func releaseVoiceShortcut(ifGeneration expected: UInt64? = nil) {
        voiceWatchdog.reset()
        releaseLegacyVoiceKey()
        if voiceToggle.isHeld { VoiceEventDiagnostics.record("RELEASE held=true generation=\(voiceToggle.generation)") }
        releaseWorkItem?.cancel()
        releaseWorkItem = nil
        _ = voiceToggle.release(ifGeneration: expected)
        isVoiceKeyHeld = voiceToggle.isHeld
    }
    private func handleLegacyVoiceKey(_ edge: RemoteEventEdge) {
        guard edge == .down else { releaseLegacyVoiceKey(); return }
        guard ready, buttons.active, !activeVoiceKey.usesToggle,
              legacyVoiceRelease == nil, VoiceToggleShortcut.isTrusted,
              let source = CGEventSource(stateID: .privateState) else { return }
        let code: CGKeyCode
        let flags: CGEventFlags
        switch activeVoiceKey {
        case .rightOption: code = 61; flags = .maskAlternate
        case .f20: code = 90; flags = []
        case .leftControl, .fn: return
        }
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { return }
        if activeVoiceKey != .f20 { down.type = .flagsChanged; up.type = .flagsChanged }
        down.flags = flags
        up.flags = []
        for event in [down, up] { event.setIntegerValueField(.eventSourceUserData, value: KeyboardInjector.syntheticEventMarker) }
        legacyVoiceRelease = up
        down.post(tap: .cghidEventTap)
        isVoiceKeyHeld = true
    }

    private func releaseLegacyVoiceKey() {
        guard let event = legacyVoiceRelease else { return }
        event.post(tap: .cghidEventTap)
        legacyVoiceRelease = nil
        isVoiceKeyHeld = voiceToggle.isHeld
    }

    private func resetAudioMeter() {
        audioMeter = AudioInputMeter()
        level = 0
        peakDBFS = nil
        audioOverloaded = false
        lastMeterAt = .distantPast
    }

    func bluetoothBridge(_ bridge: XiaomiBluetoothBridge, didDecode samples: [Int16]) {
        guard isSpeaking, audioReady else { return }
        if !output.enqueue(samples, completion: nil) {
            guard recoverAudioOutput(), output.enqueue(samples, completion: nil) else { return }
        }
        voiceWatchdog.receivedAudio(at: uptime())
        audioMeter.append(samples)
        if audioMeter.overloaded && !audioOverloaded { audioOverloaded = true }
        if Date().timeIntervalSince(lastMeterAt) >= 0.08 {
            sampleCount = audioMeter.sampleCount
            peakDBFS = audioMeter.peakDBFS
            level = audioMeter.displayLevel
            audioMeter.clearPeak()
            lastMeterAt = Date()
        }
    }
}
