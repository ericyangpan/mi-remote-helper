import AppKit
import Combine
import Foundation
import IOKit.hid

final class ButtonMappingModel: ObservableObject {
    private let defaults: UserDefaults
    @Published private(set) var bindings: [String: ButtonBinding]
    @Published private(set) var doubleBindings: [String: ButtonBinding]
    @Published private(set) var holdBindings: [String: ButtonBinding]
    @Published private(set) var applicationProfiles: [ApplicationMapping]
    @Published private(set) var selectedProfileID = "global"
    @Published private(set) var frontmostBundleIdentifier: String?
    private var activationObserver: NSObjectProtocol?
    @Published private(set) var enabled: Bool
    @Published private(set) var active = false
    @Published private(set) var pressed = Set<RemoteButton>()
    @Published private(set) var longPressed = Set<RemoteButton>()
    @Published private(set) var shortPressed = Set<RemoteButton>()
    @Published private(set) var doublePressed = Set<RemoteButton>()
    @Published private(set) var lastButton: RemoteButton?
    @Published private(set) var status = String(localized: "Button mapping is off.")
    var onAvailabilityChange: (() -> Void)?
    var onVoiceMappingEdge: ((RemoteEventEdge) -> Void)?
    var canEdit: () -> Bool = { true }
    private var connected = false
    private var reader: (any RemoteButtonReading)?
    private var pendingRestoreReader: (any RemoteButtonReading)?
    private var restorationTimer: Timer?
    @Published private(set) var restorationError: String?
    private let makeReader: () -> any RemoteButtonReading
    private let hasInputMonitoring: () -> Bool
    private let hasAccessibility: () -> Bool
    private var edges = RemoteButtonEdges()
    private var holdTimers: [UInt16: Timer] = [:]
    private var tapTimers: [RemoteButton: Timer] = [:]
    private var buttonPresses = ButtonPressTracker()
    private var gestureFeedback = ButtonGestureFeedback()
    private var feedbackTimers: [RemoteButton: Timer] = [:]
    private let switcherKeyboard = AppSwitcherKeyboard()
    private lazy var appSwitcher = AppSwitcherSession(
        begin: { [switcherKeyboard] in switcherKeyboard.begin() },
        step: { [switcherKeyboard] in switcherKeyboard.step(backward: $0) },
        finish: { [switcherKeyboard] in switcherKeyboard.finish(cancel: $0) })
    private var switcherTimeout: Timer?
    var recording = false {
        didSet { if recording { cancelPendingActions() } }
    }

    init(defaults: UserDefaults = .standard,
         makeReader: @escaping () -> any RemoteButtonReading = { RemoteButtonReader() },
         hasInputMonitoring: @escaping () -> Bool = { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted },
         hasAccessibility: @escaping () -> Bool = { VoiceToggleShortcut.isTrusted }) {
        self.defaults = defaults
        self.makeReader = makeReader
        self.hasInputMonitoring = hasInputMonitoring
        self.hasAccessibility = hasAccessibility
        enabled = defaults.bool(forKey: "buttonMappingEnabled")
        if let data = defaults.data(forKey: "applicationMappings.v1"),
           let stored = try? JSONDecoder().decode([ApplicationMapping].self, from: data) {
            var identifiers = Set<String>()
            applicationProfiles = stored.filter {
                $0.definition.scope == .application && (try? $0.definition.validate()) != nil && identifiers.insert($0.id).inserted
            }
        } else { applicationProfiles = [ApplicationMapping(definition: .codex)] }
        frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let decoded = Self.decode(defaults.data(forKey: "buttonMappings.v1"))
        let decodedHolds = Self.decode(defaults.data(forKey: "buttonHoldMappings.v1"))
        let decodedDoubles = Self.decode(defaults.data(forKey: "buttonDoubleMappings.v1"))
        doubleBindings = Self.validated(decodedDoubles)
        bindings = Self.validated(decoded)
        holdBindings = Self.validated(decodedHolds)
        if bindings != decoded || holdBindings != decodedHolds || doubleBindings != decodedDoubles { save() }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.frontmostApplicationChanged(to: app?.bundleIdentifier)
        }

    }

    private static func decode(_ data: Data?) -> [String: ButtonBinding] {
        data.flatMap { try? JSONDecoder().decode([String: ButtonBinding].self, from: $0) } ?? [:]
    }

    private static func validated(_ values: [String: ButtonBinding]) -> [String: ButtonBinding] {
        values.filter { key, binding in
            guard let button = RemoteButton(rawValue: key), button != .microphone else { return false }
            switch binding {
            case .shortcut(let chord): return chord.isValid
            case .dictation: return false
            case .preset: return true
            }
        }
    }

    func binding(for button: RemoteButton, press: ButtonPressKind = .tap, profileID: String = "global") -> ButtonBinding {
        if profileID != "global", button != .microphone,
           let entry = applicationProfiles.first(where: { $0.id == profileID }),
           let override = entry.definition.override(for: button, press: press) { return override }
        guard button != .microphone else { return .dictation }
        switch press {
        case .tap: return bindings[button.rawValue] ?? button.defaultBinding
        case .hold: return holdBindings[button.rawValue] ?? button.defaultHoldBinding
        case .doubleTap: return doubleBindings[button.rawValue] ?? button.defaultDoubleBinding
        }
    }

    @discardableResult
    func setBinding(_ binding: ButtonBinding, for button: RemoteButton, press: ButtonPressKind = .tap, profileID: String = "global") -> Bool {
        guard button != .microphone, canEdit(), pressed.isEmpty else { return false }
        if case .dictation = binding { return false }
        if case .shortcut(let chord) = binding, !chord.isValid { return false }
        cancelPendingActions()
        if profileID != "global" {
            guard let index = applicationProfiles.firstIndex(where: { $0.id == profileID }) else { return false }
            applicationProfiles[index].definition.set(binding, for: button, press: press)
            save()
            return true
        }
        switch press {
        case .tap: bindings[button.rawValue] = binding
        case .hold: holdBindings[button.rawValue] = binding
        case .doubleTap: doubleBindings[button.rawValue] = binding
        }
        save()
        return true
    }

    func reset(profileID: String = "global") {
        guard canEdit(), pressed.isEmpty else { return }
        cancelPendingActions()
        if profileID == "global" {
            doubleBindings = [:]
            bindings = [:]
            holdBindings = [:]
        } else if let index = applicationProfiles.firstIndex(where: { $0.id == profileID }) {
            applicationProfiles[index].definition.shortPress = [:]
            applicationProfiles[index].definition.longPress = [:]
            applicationProfiles[index].definition.doublePress = [:]
        }
        save()
        onAvailabilityChange?()
    }
    private func save() {
        if let data = try? JSONEncoder().encode(doubleBindings) { defaults.set(data, forKey: "buttonDoubleMappings.v1") }
        if let data = try? JSONEncoder().encode(applicationProfiles) { defaults.set(data, forKey: "applicationMappings.v1") }
        if let data = try? JSONEncoder().encode(bindings) { defaults.set(data, forKey: "buttonMappings.v1") }
        if let data = try? JSONEncoder().encode(holdBindings) { defaults.set(data, forKey: "buttonHoldMappings.v1") }
    }

    deinit {
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        switcherTimeout?.invalidate()
        restorationTimer?.invalidate()
    }

    var globalDefinition: MappingDefinition {
        let buttons = RemoteButton.allCases.filter { $0 != .microphone }
        return MappingDefinition(name: "Global", scope: .global,
            shortPress: Dictionary(uniqueKeysWithValues: buttons.map { ($0.rawValue, binding(for: $0)) }),
            longPress: Dictionary(uniqueKeysWithValues: buttons.map { ($0.rawValue, binding(for: $0, press: .hold)) }),
            doublePress: Dictionary(uniqueKeysWithValues: buttons.map { ($0.rawValue, binding(for: $0, press: .doubleTap)) }))
    }
    var activeProfileName: String {
        applicationProfiles.first { $0.enabled && $0.definition.bundleIdentifier == frontmostBundleIdentifier }?.definition.name
            ?? String(localized: "Global")
    }
    var selectedApplication: ApplicationMapping? { applicationProfiles.first { $0.id == selectedProfileID } }

    func selectProfile(_ id: String) {
        guard canEdit(), pressed.isEmpty, id == "global" || applicationProfiles.contains(where: { $0.id == id }) else { return }
        cancelPendingActions()
        selectedProfileID = id
    }
    func inheritsGlobal(_ button: RemoteButton, press: ButtonPressKind, profileID: String) -> Bool {
        profileID != "global" && applicationProfiles.first(where: { $0.id == profileID })?.definition.override(for: button, press: press) == nil
    }
    func inheritGlobal(_ button: RemoteButton, press: ButtonPressKind, profileID: String) {
        guard button != .microphone, canEdit(), pressed.isEmpty,
              let index = applicationProfiles.firstIndex(where: { $0.id == profileID }) else { return }
        cancelPendingActions()
        applicationProfiles[index].definition.set(nil, for: button, press: press)
        save()
    }
    func setApplicationEnabled(_ value: Bool, profileID: String) {
        guard canEdit(), pressed.isEmpty, let index = applicationProfiles.firstIndex(where: { $0.id == profileID }) else { return }
        cancelPendingActions()
        applicationProfiles[index].enabled = value
        save()
    }
    func addApplication(name: String, bundleIdentifier: String) throws {
        guard canEdit(), pressed.isEmpty else { throw MappingDefinitionError.busy }
        let definition = MappingDefinition(name: name, scope: .application, bundleIdentifier: bundleIdentifier, shortPress: [:], longPress: [:])
        try definition.validate()
        if !applicationProfiles.contains(where: { $0.id == definition.id }) {
            applicationProfiles.append(ApplicationMapping(definition: definition))
            save()
        }
        selectedProfileID = definition.id
    }
    func removeApplication(_ id: String) {
        guard canEdit(), pressed.isEmpty else { return }
        cancelPendingActions()
        applicationProfiles.removeAll { $0.id == id }
        if selectedProfileID == id { selectedProfileID = "global" }
        save()
    }
    func exportDefinition(profileID: String) throws -> MappingDefinition {
        if profileID == "global" { return globalDefinition }
        guard let entry = applicationProfiles.first(where: { $0.id == profileID }) else { throw MappingDefinitionError.invalidDefinition }
        return entry.definition
    }
    func importDefinition(_ definition: MappingDefinition) throws {
        try definition.validate()
        guard canEdit(), pressed.isEmpty else { throw MappingDefinitionError.busy }
        cancelPendingActions()
        if definition.scope == .global {
            bindings = definition.shortPress
            holdBindings = definition.longPress
            doubleBindings = definition.doublePress
        } else if let index = applicationProfiles.firstIndex(where: { $0.id == definition.id }) {
            applicationProfiles[index].definition = definition
        } else { applicationProfiles.append(ApplicationMapping(definition: definition)) }
        selectedProfileID = definition.id
        save()
    }

    func frontmostApplicationChanged(to identifier: String?) {
        // Cancel even if two activations have the same bundle ID (different instances).
        cancelPendingActions()
        frontmostBundleIdentifier = identifier
    }
    @discardableResult private func synchronizeForeground() -> Bool {
        let identifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard identifier != frontmostBundleIdentifier else { return false }
        frontmostApplicationChanged(to: identifier)
        return true
    }
    func runtimeBinding(for button: RemoteButton, press: ButtonPressKind) -> ButtonBinding {
        MappingResolver.binding(for: button, press: press, global: globalDefinition,
            applications: applicationProfiles, frontmostBundleIdentifier: frontmostBundleIdentifier)
    }

    func setEnabled(_ value: Bool) {
        guard canEdit(), pressed.isEmpty else { return }
        enabled = value
        defaults.set(value, forKey: "buttonMappingEnabled")
        refresh(connected: connected)
        onAvailabilityChange?()
    }

    func refresh(connected: Bool) {
        self.connected = connected
        guard pendingRestoreReader == nil else { return }
        guard enabled else { setUnavailableStatus(String(localized: "Button mapping is off.")); return }
        guard connected else { setUnavailableStatus(String(localized: "Connect the remote to use button mappings.")); return }
        guard hasInputMonitoring() else {
            setUnavailableStatus(String(localized: "Allow Input Monitoring to enable button mappings.")); return
        }
        guard hasAccessibility() else {
            setUnavailableStatus(String(localized: "Allow Accessibility to send shortcuts.")); return
        }
        guard reader == nil else { return }
        let reader = makeReader()
        self.reader = reader
        reader.onActive = { [weak self] active, error in
            guard let self else { return }
            self.clearPressed()
            self.active = active
            self.status = error ?? (active ? String(localized: "Button mappings are ready.") : String(localized: "Waiting for the remote’s buttons…"))
            if !active, self.reader?.restorationPending == true {
                self.stop()
                self.onAvailabilityChange?()
                return
            }
            self.onAvailabilityChange?()
        }
        reader.onReport = { [weak self] in self?.handle($0) }
        reader.start()
    }

    private func setUnavailableStatus(_ message: String) {
        if reader != nil || active { stop() }
        let displayed = restorationError ?? message
        if status != displayed { status = displayed }
    }

    private func stop() {
        if let reader {
            reader.onActive = nil
            reader.onReport = nil
            if !reader.stop() {
                // Keep the mapper and its original values alive until restoration succeeds.
                pendingRestoreReader = reader
                let error = String(localized: "Unable to restore the remote’s buttons. Retrying; reconnect the remote if this continues.")
                restorationError = error
                status = error
                if restorationTimer == nil {
                    let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.retryPendingRestoration() }
                    restorationTimer = timer
                    RunLoop.main.add(timer, forMode: .common)
                }
            }
        }
        reader = nil
        clearPressed()
        if active { active = false; onAvailabilityChange?() }
    }

    func retryPendingRestoration() {
        guard let pendingRestoreReader, pendingRestoreReader.stop() else { return }
        self.pendingRestoreReader = nil
        restorationTimer?.invalidate()
        restorationTimer = nil
        restorationError = nil
        refresh(connected: connected)
    }

    /// Called by ATVV too: HID delivery is not ordered ahead of voice controls.
    func prepareForVoiceInput() -> Bool {
        cancelPendingActions()
        return switcherKeyboard.commandReleasePending
    }

    private func cancelPendingActions(preserveFeedback: Bool = false) {
        appSwitcher.finish(cancel: true)
        switcherTimeout?.invalidate()
        switcherTimeout = nil
        tapTimers.values.forEach { $0.invalidate() }
        tapTimers.removeAll()
        holdTimers.values.forEach { $0.invalidate() }
        holdTimers.removeAll()
        buttonPresses.cancel()
        if !preserveFeedback {
            gestureFeedback.cancel()
            feedbackTimers.values.forEach { $0.invalidate() }
            feedbackTimers.removeAll()
            shortPressed = []
            doublePressed = []
            longPressed = []
        }
    }

    private func clearPressed() {
        cancelPendingActions()
        _ = appSwitcher.handle(pressed: [], down: [])
        if pressed.contains(.microphone), binding(for: .microphone) == .dictation { onVoiceMappingEdge?(.up) }
        edges.reset()
        pressed = []
    }

    private func send(_ binding: ButtonBinding) {
        guard !synchronizeForeground() else { return }
        if binding == .preset(.appSwitcher) {
            cancelPendingActions(preserveFeedback: true)
            if appSwitcher.begin(held: pressed) {
                switcherTimeout = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
                    self?.cancelPendingActions()
                }
            } else {
                status = String(localized: "Unable to send the shortcut. Check Accessibility permission.")
            }
            return
        }
        if !KeyboardInjector.send(binding) { status = String(localized: "Unable to send the shortcut. Check Accessibility permission.") }
    }

    private func scheduleTap(for button: RemoteButton) {
        tapTimers.removeValue(forKey: button)?.invalidate()
        guard let deadline = buttonPresses.deadline(for: button) else { return }
        let timer = Timer(timeInterval: max(0.001, deadline - ProcessInfo.processInfo.systemUptime), repeats: false) { [weak self] _ in
            guard let self, !self.synchronizeForeground(), self.active, !self.recording else { return }
            guard VoiceToggleShortcut.isTrusted,
                  IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted else {
                self.cancelPendingActions(); return
            }
            if let action = self.buttonPresses.flush(button, at: ProcessInfo.processInfo.systemUptime) {
                self.tapTimers.removeValue(forKey: button)
                self.send(action)
            } else { self.scheduleTap(for: button) }
        }
        tapTimers[button] = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func feedbackKind(for button: RemoteButton) -> ButtonPressKind? {
        if longPressed.contains(button) { return .hold }
        if doublePressed.contains(button) { return .doubleTap }
        if shortPressed.contains(button) { return .tap }
        return nil
    }

    private func clearFeedback(for button: RemoteButton) {
        feedbackTimers.removeValue(forKey: button)?.invalidate()
        shortPressed.remove(button)
        doublePressed.remove(button)
        longPressed.remove(button)
    }

    private func showFeedback(_ kind: ButtonPressKind, for button: RemoteButton, released: Bool = true) {
        clearFeedback(for: button)
        switch kind {
        case .tap: shortPressed.insert(button)
        case .doubleTap: doublePressed.insert(button)
        case .hold: longPressed.insert(button)
        }
        guard released else { return }
        let timer = Timer(timeInterval: 0.65, repeats: false) { [weak self] _ in
            self?.clearFeedback(for: button)
        }
        feedbackTimers[button] = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func handle(_ usages: Set<UInt16>) {
        guard active else { return }
        guard VoiceToggleShortcut.isTrusted, IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted else {
            refresh(connected: connected); return
        }
        synchronizeForeground()
        let incoming = Set(usages.compactMap { RemoteButton.usageMap[$0] })
        let newButtons = incoming.subtracting(pressed)
        for button in buttonPresses.pendingButtons {
            if let action = buttonPresses.flush(button, at: ProcessInfo.processInfo.systemUptime,
                                                force: !newButtons.subtracting([button]).isEmpty) {
                tapTimers.removeValue(forKey: button)?.invalidate()
                if !recording { send(action) }
            }
        }
        let changes = edges.update(usages)
        pressed = Set(usages.compactMap { RemoteButton.usageMap[$0] })
        let consumed = appSwitcher.handle(pressed: pressed,
            down: Set(changes.down.compactMap { RemoteButton.usageMap[$0] }))
        if !appSwitcher.isActive { switcherTimeout?.invalidate(); switcherTimeout = nil }
        for usage in changes.up {
            holdTimers.removeValue(forKey: usage)?.invalidate()
            if let button = RemoteButton.usageMap[usage], !recording,
               let kind = gestureFeedback.release(button, at: ProcessInfo.processInfo.systemUptime) {
                showFeedback(kind, for: button)
            }
            if let button = RemoteButton.usageMap[usage], consumed.contains(button) { continue }
            if let button = RemoteButton.usageMap[usage],
               let action = buttonPresses.release(button, at: ProcessInfo.processInfo.systemUptime), !recording {
                send(action)
            }
            if let button = RemoteButton.usageMap[usage] { scheduleTap(for: button) }
            if usage == RemoteButton.microphone.hidUsage, binding(for: .microphone) == .dictation { onVoiceMappingEdge?(.up) }
        }
        guard !recording else { return }
        for usage in changes.down.sorted() {
            guard let button = RemoteButton.usageMap[usage] else { continue }
            lastButton = button
            if consumed.contains(button) { continue }
            clearFeedback(for: button)
            gestureFeedback.begin(button, at: ProcessInfo.processInfo.systemUptime)
            let binding = runtimeBinding(for: button, press: .tap)
            if binding == .dictation { onVoiceMappingEdge?(.down); continue }
            if let generation = buttonPresses.begin(button, tap: binding, hold: runtimeBinding(for: button, press: .hold), doubleTap: runtimeBinding(for: button, press: .doubleTap), at: ProcessInfo.processInfo.systemUptime) {
                tapTimers.removeValue(forKey: button)?.invalidate()
                let timer = Timer(timeInterval: ButtonPressTracker.holdDuration, repeats: false) { [weak self] _ in
                    guard let self, !self.synchronizeForeground(), self.active, !self.recording, self.pressed.contains(button),
                          VoiceToggleShortcut.isTrusted,
                          IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted,
                          let action = self.buttonPresses.fire(button, generation: generation, at: ProcessInfo.processInfo.systemUptime) else { return }
                    self.showFeedback(.hold, for: button, released: false)
                    self.send(action)
                }
                holdTimers[usage] = timer
                RunLoop.main.add(timer, forMode: .common)
                continue
            }
        }
    }
}
