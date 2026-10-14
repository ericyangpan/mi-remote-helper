import AppKit
import Combine
import CoreBluetooth
import IOKit.hid

final class BridgeModel: ObservableObject, XiaomiBluetoothBridgeDelegate {
    let settings: AppSettings
    let buttons: ButtonMappingModel
    private lazy var batteryNotifications = LowBatteryNotifications()
    private var legacyVoiceRelease: CGEvent?
    @Published private(set) var state: BluetoothBridgeState = .stopped
    @Published private(set) var batteryCharging: Bool?
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
    @Published private(set) var message = String.appStatus("Select a virtual microphone, then connect the remote.")
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
    private var suppressVoiceAudio = false
    private struct PendingVoicePress {
        let startedAt: TimeInterval
        let app: String?
        let binding: ButtonBinding
        let clearSwitcherCommand: Bool
    }
    private var pendingVoicePress: PendingVoicePress?
    private var voiceTapTracker = ButtonPressTracker()
    private var voiceTapTimer: Timer?
    private var voiceTapApp: String?
    private var voiceTapIsSecond = false
    private var voiceTapGeneration: UInt64 = 0
    private var voiceHoldTimer: Timer?
    private var voicePressGeneration: UInt64 = 0
    private var physicalVoiceKeyDown = false
    private var pendingVoiceSamples: [Int16] = []
    private static let maximumPendingVoiceSamples = 8_000
    private var voiceStreamStarted = false
    private var voiceActivationObserver: NSObjectProtocol?
    private let postLegacyEvent: (CGEvent) -> Void
    private let voiceToggle: VoiceToggleShortcut
    private let voiceDiagnostics = VoiceEventDiagnostics()
    private var releaseWorkItem: DispatchWorkItem?
    private let makeTransport: (AppSettings, XiaomiBluetoothBridgeDelegate) -> any RemoteVoiceTransport
    private lazy var remote = makeTransport(settings, self)
    private let readPermissions: () -> BridgePermissions
    private let listDevices: () -> [AudioDeviceInfo]
    private let uptime: () -> TimeInterval
    private var pendingSettingsApply = false
    private var launchConnectionChecked = false
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
         postLegacyEvent: @escaping (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) },
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
        self.postLegacyEvent = postLegacyEvent
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
        voiceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.cancelVoiceGestureForApplicationChange()
        }
        refreshDevices()
        refreshPermissions()
        if !settings.outputUID.isEmpty { message = String.appStatus("Connect the remote to start voice input.") }
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

    deinit {
        if let voiceActivationObserver { NSWorkspace.shared.notificationCenter.removeObserver(voiceActivationObserver) }
        voiceHoldTimer?.invalidate()
        voiceTapTimer?.invalidate()
    }

    func refreshDevices() {
        let devices = listDevices()
        if outputs != devices { outputs = devices }
        if settings.outputUID.isEmpty, outputs.count == 1 { settings.outputUID = outputs[0].uid }
    }

    func startAtLaunchIfNeeded() {
        guard !launchConnectionChecked else { return }
        launchConnectionChecked = true
        guard settings.connectAtLaunch, settings.peripheralIdentifier != nil,
              !settings.outputUID.isEmpty, readPermissions().bluetooth else { return }
        start()
    }

    func start() {
        guard !isRunning else { return }
        refreshDevices()
        isRunning = true
        sampleCount = 0
        remote.setVoiceBridgingEnabled(false)
        message = String.appStatus("Press a button to wake the remote and keep it paired in Bluetooth settings.")
        remote.start()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.checkHealth() }
        healthTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        cancelVoiceTaps()
        physicalVoiceKeyDown = false
        healthTimer?.invalidate()
        healthTimer = nil
        isRunning = false
        suppressVoiceAudio = false
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
        message = buttons.restorationError ?? (voiceRestored ? String.appStatus("Stopped. The original voice key mapping has been restored.") : (mapper.error ?? String.appStatus("Please reconnect the remote.")))
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
            audioOutputFailed(message: String.appStatus("Restoring the virtual microphone as system input…"))
            scheduleAudioRecovery()
            return
        }
        guard mapper.restore() else {
            message = mapper.error ?? String.appStatus("Unable to restore the voice key mapping.")
            if inputMonitoringAllowed { scheduleAudioRecovery() }
            return
        }
        refreshPermissions()
        if !accessibilityAllowed {
            output.stop()
            audioReady = false
            message = String.appStatus("Allow Accessibility, then apply settings to enable voice shortcuts.")
            return
        }
        audioReady = output.configure(uid: settings.outputUID)
        guard audioReady else {
            message = output.error ?? String.appStatus("The virtual microphone is not ready.")
            scheduleAudioRecovery()
            return
        }
        audioRecoveryPending = false
        keyReady = mapper.apply(.leftControl)
        if keyReady { voiceDiagnostics.start() }
        if keyReady { activeVoiceKey = settings.voiceKey }
        remote.setVoiceBridgingEnabled(keyReady)
        if keyReady {
            message = activeVoiceKey.usesToggle
                ? String.appStatus("Set the selected shortcut to toggle dictation in WeChat. Hold the remote’s voice button to speak and release it to finish.")
                : String.appStatus("Set the matching shortcut in your input method, then hold the remote’s voice button to speak.")
        } else {
            message = mapper.error ?? String.appStatus("The voice key is not ready.")
            if inputMonitoringAllowed { scheduleAudioRecovery() }
        }
    }

    func playTestTone() {
        guard !isSpeaking, !isVoiceKeyHeld, !testToneActive else { return }
        if !output.isReady || output.deviceUID != settings.outputUID {
            if isConnected { applySettings() }
            else { audioReady = output.configure(uid: settings.outputUID) }
        }
        guard audioReady, output.isReady, output.deviceUID == settings.outputUID else {
            testToneMessage = output.error ?? String.appStatus("The virtual microphone is not ready.")
            return
        }
        cancelTestTone()
        testToneActive = true
        testToneMessage = String.appStatus("Sending a test tone to the virtual microphone. Check the input level in Sound settings.")
        let token = testToneGeneration
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.testToneActive, self.testToneGeneration == token else { return }
            let message = String.appStatus("Test tone timed out. Apply settings and try again.")
            self.audioOutputFailed(message: message)
            self.testToneMessage = message
        }
        testToneTimeout = timeout
        // This also runs when testing without a Bluetooth connection/health timer.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: timeout)
        let queued = output.testTone { [weak self] in
            guard let self, self.testToneGeneration == token, self.testToneActive else { return }
            self.cancelTestTone()
            self.testToneMessage = String.appStatus("Test tone sent. Check that the input level changed in Sound settings.")
        }
        if !queued {
            cancelTestTone()
            testToneMessage = output.error ?? String.appStatus("Unable to play the test tone.")
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
        audioOutputFailed(message: String.appStatus("Restoring the virtual microphone…"))
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
                    audioOutputFailed(message: String.appStatus("Restoring the virtual microphone as system input…"))
                }
                if !audioRecoveryPending { scheduleAudioRecovery() }
                return
            }
        }
        if keyReady, !accessibilityAllowed {
            releaseVoiceShortcut()
            remote.setVoiceBridgingEnabled(false)
            keyReady = false
            _ = mapper.restore()
            message = String.appStatus("Accessibility access is unavailable. Grant permission, then apply settings again.")
        }
        if audioReady && (!output.isDeviceAlive || !output.isReady) {
            recoverAudioOutput()
        }
        if let failure = voiceWatchdog.failure(at: uptime()) {
            VoiceEventDiagnostics.record("VOICE timeout=\(failure)")
            voiceWatchdog.reset()
            message = String.appStatus("Remote audio was interrupted. Reconnecting.")
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
            cancelVoiceTaps()
            physicalVoiceKeyDown = false
            suppressVoiceAudio = false
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
                message = String.appStatus("Allow Bluetooth when prompted, or grant Mi Remote Helper access in Bluetooth privacy settings.")
            case .initializingBluetooth:
                message = String.appStatus("Initializing Bluetooth. If it does not connect, check Bluetooth permission and try again.")
            case .bluetoothUnavailable(let reason):
                message = String.appStatus("\(reason). Check Bluetooth and this app’s Bluetooth permission in System Settings.")
            case .scanning:
                message = String.appStatus("Press a button to wake the remote and keep it paired in Bluetooth settings.")
            case .connecting, .discovering, .reconnecting:
                message = state.displayText + "…"
            case .failed(let reason): message = reason
            case .stopped, .ready: break
            }
        }
    }
    func bluetoothBridge(_ bridge: XiaomiBluetoothBridge, didDetectModelNumber modelNumber: String) {}

    func bluetoothBridge(_ bridge: XiaomiBluetoothBridge, didUpdateCharging charging: Bool?) {
        batteryCharging = charging
        batteryNotifications.update(percentage: batteryLevel?.percentage, charging: charging)
    }
    func bluetoothBridge(_ bridge: XiaomiBluetoothBridge, didUpdateBatteryLevel level: RemoteBatteryLevel?) {
        batteryLevel = level
        batteryNotifications.update(percentage: level?.percentage, charging: batteryCharging)
    }
    func bluetoothBridge(_ bridge: XiaomiBluetoothBridge, didObserveVoiceKey edge: RemoteEventEdge) {
        VoiceEventDiagnostics.record("ATVV edge=\(edge) ready=\(ready) held=\(voiceToggle.isHeld)")
        switch edge {
        case .down:
            guard !physicalVoiceKeyDown else { return }
            physicalVoiceKeyDown = true
            suppressVoiceAudio = true
            // Do not run pending HID reconfiguration from inside an ATVV down
            // callback: disabling the voice gate here would cancel this new press.
            guard isRunning, isConnected else { return }
            guard updateSystemInputPolicy() else {
                audioOutputFailed(message: String.appStatus("Restoring the virtual microphone as system input…"))
                scheduleAudioRecovery()
                return
            }
            if audioReady && (!output.isDeviceAlive || !output.isReady) { recoverAudioOutput() }
            guard ready else { return }
            let clearSwitcherCommand = buttons.prepareForVoiceInput()
            // A new press must not inherit the previous session's delayed release.
            releaseVoiceShortcut(preserveTaps: true)
            guard !voiceToggle.isHeld else { message = String.appStatus("Unable to finish the previous voice shortcut. Stop and try again."); return }
            suppressVoiceAudio = true
            voiceStreamStarted = false
            isSpeaking = false
            isVoiceKeyHeld = true
            pendingVoicePress = PendingVoicePress(startedAt: uptime(),
                app: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                binding: buttons.voiceTapBinding(), clearSwitcherCommand: clearSwitcherCommand)
            flushVoiceTap()
            voiceTapTimer?.invalidate()
            voiceTapIsSecond = voiceTapTracker.deadline(for: .microphone).map { uptime() < $0 } ?? false
            voiceTapApp = pendingVoicePress?.app
            _ = voiceTapTracker.begin(.microphone, tap: buttons.voiceTapBinding(), hold: .dictation,
                                      doubleTap: buttons.voiceTapBinding(press: .doubleTap), at: uptime(), allowVoice: true)
            voiceWatchdog.press(at: uptime())
            scheduleVoiceHold(after: ButtonPressTracker.holdDuration)
        case .up:
            guard physicalVoiceKeyDown else { return }
            physicalVoiceKeyDown = false
            defer { buttons.finishVoiceFeedback() }
            if let pending = pendingVoicePress {
                if uptime() - pending.startedAt >= ButtonPressTracker.holdDuration {
                    activatePendingVoiceHold()
                } else {
                    cancelPendingVoicePress()
                    voiceWatchdog.reset()
                    isVoiceKeyHeld = false
                    if let binding = voiceTapTracker.release(.microphone, at: uptime()) {
                        buttons.sendVoiceTap(binding, originatingApp: pending.app, press: voiceTapIsSecond ? .doubleTap : .tap)
                    } else {
                        scheduleVoiceTap()
                    }
                    return
                }
            }
            voiceWatchdog.reset()
            if suppressVoiceAudio { isVoiceKeyHeld = false; return }
            finishVoiceShortcut()
        }
    }
    func bluetoothBridgeDidStartVoice(_ bridge: XiaomiBluetoothBridge) {
        VoiceEventDiagnostics.record("AUDIO start held=\(voiceToggle.isHeld)")
        guard ready else { return }
        if suppressVoiceAudio { voiceStreamStarted = true; voiceWatchdog.receivedAudio(at: uptime()); return }
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
        message = String.appStatus("Receiving audio from the remote…")
    }
    func bluetoothBridgeDidStopVoice(_ bridge: XiaomiBluetoothBridge) {
        if suppressVoiceAudio {
            voiceStreamStarted = false
            // The key-up notification can follow AUDIO_STOP; keep the pending tap until then.
            if pendingVoicePress == nil { voiceWatchdog.reset(); isVoiceKeyHeld = false }
            return
        }
        physicalVoiceKeyDown = false
        sampleCount = audioMeter.sampleCount
        voiceWatchdog.reset()
        VoiceEventDiagnostics.record("AUDIO stop queued=\(output.queuedFrames) held=\(voiceToggle.isHeld)")
        finishVoiceShortcut()
        isSpeaking = false
        level = 0
        peakDBFS = nil
        // Leave queued tail audio to finish playing. Starting another session flushes it.
        if isRunning { message = sampleCount > 0 ? AppLocalization.shared.format("Received %.1f seconds of audio. WeChat Input handles transcription.", seconds: audioSeconds) : String.appStatus("No audio received. Hold the voice button and try again.") }
    }

    private func cancelVoiceTaps() {
        voiceTapGeneration &+= 1
        voiceTapTimer?.invalidate()
        voiceTapTimer = nil
        voiceTapTracker.cancel()
        voiceTapApp = nil
    }

    private func scheduleVoiceTap() {
        voiceTapTimer?.invalidate()
        guard let deadline = voiceTapTracker.deadline(for: .microphone) else { return }
        let generation = voiceTapGeneration
        let timer = Timer(timeInterval: max(0.001, deadline - uptime()), repeats: false) { [weak self] _ in
            guard let self, self.voiceTapGeneration == generation else { return }
            self.flushVoiceTap()
            self.scheduleVoiceTap()
        }
        voiceTapTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func flushVoiceTap() {
        if let binding = voiceTapTracker.flush(.microphone, at: uptime()) {
            buttons.sendVoiceTap(binding, originatingApp: voiceTapApp)
        }
    }

    func cancelVoiceGestureForApplicationChange() {
        cancelVoiceTaps()
        guard pendingVoicePress != nil else { return }
        cancelPendingVoicePress()
        isVoiceKeyHeld = false
        voiceWatchdog.reset()
    }

    private func cancelPendingVoicePress() {
        voicePressGeneration &+= 1
        pendingVoiceSamples.removeAll(keepingCapacity: true)
        pendingVoicePress = nil
        voiceHoldTimer?.invalidate()
        voiceHoldTimer = nil
    }

    private func scheduleVoiceHold(after delay: TimeInterval) {
        voiceHoldTimer?.invalidate()
        let generation = voicePressGeneration
        let timer = Timer(timeInterval: max(0.001, delay), repeats: false) { [weak self] _ in
            self?.activatePendingVoiceHold(expectedGeneration: generation)
        }
        voiceHoldTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    // Exposed internally for deterministic boundary and stale-callback regression tests.
    var pendingVoiceGeneration: UInt64 { voicePressGeneration }
    var pendingVoiceSampleCount: Int { pendingVoiceSamples.count }
    var hasPendingVoiceTimer: Bool { voiceHoldTimer?.isValid == true }

    func activatePendingVoiceHold(expectedGeneration: UInt64? = nil) {
        if let expectedGeneration, expectedGeneration != voicePressGeneration { return }
        guard let pending = pendingVoicePress else { return }
        let remaining = ButtonPressTracker.holdDuration - (uptime() - pending.startedAt)
        guard remaining <= 0 else {
            scheduleVoiceHold(after: remaining)
            return
        }
        cancelVoiceTaps()
        let initialSamples = pendingVoiceSamples
        cancelPendingVoicePress()
        guard ready, isVoiceKeyHeld, !buttons.recording,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == pending.app else {
            isVoiceKeyHeld = false
            return
        }
        let started: Bool
        if activeVoiceKey.usesToggle {
            started = voiceToggle.press(key: activeVoiceKey, clearSwitcherCommand: pending.clearSwitcherCommand)
        } else {
            handleLegacyVoiceKey(.down)
            started = legacyVoiceRelease != nil
        }
        guard started else {
            keyReady = false
            isVoiceKeyHeld = false
            remote.setVoiceBridgingEnabled(false)
            message = String.appStatus("Unable to send the voice shortcut. Check Accessibility permission.")
            return
        }
        suppressVoiceAudio = false
        buttons.showVoiceHoldFeedback()
        if voiceStreamStarted {
            resetAudioMeter()
            output.beginSession()
            isSpeaking = true
            cancelTestTone()
            sampleCount = 0
            message = String.appStatus("Receiving audio from the remote…")
            if !initialSamples.isEmpty { processVoiceSamples(initialSamples) }
        }
    }

    private func finishVoiceShortcut() {
        releaseLegacyVoiceKey()
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

    private func releaseVoiceShortcut(ifGeneration expected: UInt64? = nil, preserveTaps: Bool = false) {
        if let expected, (voiceToggle.generation != expected || !voiceToggle.isHeld) { return }
        if !preserveTaps { cancelVoiceTaps() }
        cancelPendingVoicePress()
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
        guard ready, !activeVoiceKey.usesToggle,
              legacyVoiceRelease == nil, accessibilityAllowed,
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
        postLegacyEvent(down)
        isVoiceKeyHeld = true
    }

    private func releaseLegacyVoiceKey() {
        guard let event = legacyVoiceRelease else { return }
        postLegacyEvent(event)
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
        if suppressVoiceAudio {
            if pendingVoicePress != nil {
                let capacity = Self.maximumPendingVoiceSamples - pendingVoiceSamples.count
                pendingVoiceSamples.append(contentsOf: samples.prefix(capacity))
            }
            if isVoiceKeyHeld { voiceWatchdog.receivedAudio(at: uptime()) }
            return
        }
        processVoiceSamples(samples)
    }

    private func processVoiceSamples(_ samples: [Int16]) {
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
