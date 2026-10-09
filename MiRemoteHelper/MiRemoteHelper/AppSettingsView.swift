import SwiftUI

struct AppSettingsView: View {
    @ObservedObject var model: BridgeModel
    @ObservedObject private var settings: AppSettings
    @StateObject private var loginItem = LoginItemSettings()
    @State private var outputUID: String
    @State private var voiceKey: VoiceKey
    @State private var keepSystemInput: Bool
    @Environment(\.scenePhase) private var scenePhase
    init(model: BridgeModel) {
        self.model = model
        settings = model.settings
        _outputUID = State(initialValue: model.settings.outputUID)
        _voiceKey = State(initialValue: model.settings.voiceKey)
        _keepSystemInput = State(initialValue: model.settings.keepSystemInput)
    }
    private var busy: Bool { model.isSpeaking || model.isVoiceKeyHeld || model.testToneActive }
    private var hasChanges: Bool { outputUID != settings.outputUID || voiceKey != settings.voiceKey || keepSystemInput != settings.keepSystemInput }
    // Allow releasing the input lock even if its virtual device has disappeared.
    private var onlyDisablingInputLock: Bool {
        !keepSystemInput && settings.keepSystemInput && outputUID == settings.outputUID && voiceKey == settings.voiceKey
    }
    private var deviceAvailable: Bool { model.outputs.contains { $0.uid == outputUID } }
    private var status: String {
        if model.testToneActive { return String(localized: "Sending Test Tone") }
        if model.isSpeaking || model.isVoiceKeyHeld { return String(localized: "Receiving Audio") }
        if hasChanges { return String(localized: "Unsaved Changes") }
        if !model.isConnected { return String(localized: "Not Connected") }
        return model.ready ? String(localized: "Ready") : String(localized: "Not Set Up")
    }
    private var statusSymbol: String {
        if model.testToneActive { return "speaker.wave.2" }
        if model.isSpeaking || model.isVoiceKeyHeld { return "waveform" }
        return !hasChanges && model.ready ? "checkmark.circle" : "info.circle"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(String(localized: "Settings")).font(AppTypography.heading)
                VStack(alignment: .leading, spacing: 18) {
                    Text(String(localized: "Audio Settings")).font(AppTypography.section)
                    SettingsField(title: String(localized: "Virtual Microphone")) {
                        Picker(String(localized: "Virtual Microphone"), selection: $outputUID) {
                            Text(String(localized: "Select a device")).tag("")
                            ForEach(model.outputs) { Text($0.name).tag($0.uid) }
                            if !outputUID.isEmpty && !deviceAvailable {
                                Text(String(localized: "Previously selected device unavailable")).tag(outputUID)
                            }
                        }.labelsHidden()

                    }
                    HStack(spacing: 10) {
                        Button(String(localized: "Refresh Devices")) { model.refreshDevices() }
                        Button(String(localized: "Play Test Tone")) { model.playTestTone() }
                            .disabled(!deviceAvailable || hasChanges)
                            .help(hasChanges ? String(localized: "Apply your changes before testing.") : String(localized: "Play Test Tone"))
                    }.padding(.leading, 196).controlSize(.small)
                    SettingsField(title: String(localized: "Keep System Input")) {
                        Toggle(String(localized: "Keep System Input"), isOn: $keepSystemInput)
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                            .accessibilityIdentifier("keepSystemInputToggle")
                            .help(String(localized: "Keep the selected virtual microphone as system input while the remote is connected."))
                    }
                    SettingsField(title: String(localized: "WeChat Voice Shortcut")) {
                        Picker(String(localized: "WeChat Voice Shortcut"), selection: $voiceKey) {
                            ForEach(VoiceKey.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                    }
                    HStack {
                        Label(status, systemImage: statusSymbol)
                            .font(AppTypography.caption).foregroundStyle(hasChanges ? AppTheme.coral : model.ready ? AppTheme.teal : AppTheme.muted)
                        Spacer()
                        if hasChanges {
                            Button(String(localized: "Revert")) { restoreSelection() }
                        }
                        Button(model.isConnected ? String(localized: "Apply Settings") : String(localized: "Save Settings")) {
                            settings.outputUID = outputUID
                            settings.voiceKey = voiceKey
                            settings.keepSystemInput = keepSystemInput
                            model.applySettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled((!deviceAvailable && !onlyDisablingInputLock) || (!hasChanges && (!model.isConnected || model.ready)))
                    }
                    if !hasChanges, let testToneMessage = model.testToneMessage {
                        Text(testToneMessage).font(AppTypography.caption).foregroundStyle(AppTheme.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    if model.inputRestorationError != nil || (!model.ready && model.isConnected) {
                        Text(model.statusMessage).font(AppTypography.caption).foregroundStyle(AppTheme.muted).fixedSize(horizontal: false, vertical: true)
                    } else if !model.isConnected {
                        Text(String(localized: "Saved settings will be used when the remote connects."))
                            .font(AppTypography.caption).foregroundStyle(AppTheme.muted)
                    }
                }.disabled(busy)
                SectionRule()
                HStack {
                    Text(String(localized: "Launch at Login"))
                    Spacer()
                    Toggle(String(localized: "Launch at Login"), isOn: Binding(get: { loginItem.isEnabled }, set: loginItem.setEnabled))
                        .labelsHidden().toggleStyle(.switch).accessibilityIdentifier("launchAtLoginToggle")
                }
                if loginItem.needsApproval {
                    Button(String(localized: "Open Login Items Settings")) { loginItem.openSystemSettings() }
                }
                if let error = loginItem.errorMessage { Text(error).foregroundStyle(AppTheme.coral).font(AppTypography.caption) }
                SectionRule()
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "Connection & Permissions")).font(AppTypography.section)
                    HStack {
                        Button(String(localized: "Bluetooth Settings")) { openSettings("com.apple.BluetoothSettings") }
                        Button(String(localized: "Sound Settings")) { openSettings("com.apple.Sound-Settings.extension") }
                        Button(String(localized: "Reconnect")) { model.reconnect() }.disabled(busy)
                    }
                    if !model.bluetoothAllowed {
                        Button(String(localized: "Bluetooth Permission")) { openSettings("com.apple.preference.security?Privacy_Bluetooth") }
                    }
                    if !model.accessibilityAllowed {
                        Button(String(localized: "Allow Accessibility")) { model.requestAccessibility() }
                    }
                    if !model.inputMonitoringAllowed {
                        Button(String(localized: "Allow Input Monitoring")) { model.requestInputMonitoring() }
                    }
                }
                DisclosureGroup(String(localized: "Getting Started")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "Pair the remote in Bluetooth settings. Choose the same virtual microphone in this app and your input method, then select the matching voice shortcut."))
                        Link(String(localized: "Install BlackHole 2ch…"), destination: URL(string: "https://existential.audio/blackhole/")!)
                        Text(String(localized: "Audio stays on this Mac and is not recorded. WeChat Input handles speech recognition."))
                    }.font(AppTypography.body).foregroundStyle(AppTheme.muted).padding(.top, 8)
                }
            }.padding(32)
        }
        .frame(width: 590, height: 620).background(AppTheme.canvas)
        .font(AppTypography.body)
        .foregroundStyle(AppTheme.ink).tint(AppTheme.teal)
        .onAppear { refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }
    private func restoreSelection() {
        outputUID = settings.outputUID
        voiceKey = settings.voiceKey
        keepSystemInput = settings.keepSystemInput
    }
    private func refresh() {
        let preserveDraft = hasChanges
        model.refreshDevices(); model.refreshPermissions(); loginItem.refresh()
        if !preserveDraft { restoreSelection() }
    }
    private func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:\(pane)") { NSWorkspace.shared.open(url) }
    }
}

private struct SettingsField<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 16) {
            Text(title).font(AppTypography.body).frame(width: 180, alignment: .leading)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
