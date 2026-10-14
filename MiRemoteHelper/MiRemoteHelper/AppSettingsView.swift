import SwiftUI

struct AppSettingsView: View {
    @ObservedObject private var localization = AppLocalization.shared
    @ObservedObject var model: BridgeModel
    @ObservedObject private var settings: AppSettings
    @StateObject private var loginItem = LoginItemSettings()
    @State private var outputUID: String
    @State private var voiceKey: VoiceKey
    @State private var keepSystemInput: Bool
    @State private var selectedSection: SettingsSection = .audio
    @State private var showsGettingStarted = false
    private enum SettingsSection { case general, audio, connection }
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
        if model.testToneActive { return String.appLocalized("Sending Test Tone") }
        if model.isSpeaking || model.isVoiceKeyHeld { return String.appLocalized("Receiving Audio") }
        if hasChanges { return String.appLocalized("Unsaved Changes") }
        if !model.isConnected { return String.appLocalized("Not Connected") }
        return model.ready ? String.appLocalized("Ready") : String.appLocalized("Not Set Up")
    }
    private var statusSymbol: String {
        if model.testToneActive { return "speaker.wave.2" }
        if model.isSpeaking || model.isVoiceKeyHeld { return "waveform" }
        return !hasChanges && model.ready ? "checkmark.circle" : "info.circle"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text(String.appLocalized("Settings")).font(AppTypography.heading)
                Spacer()
                Button { showsGettingStarted = true } label: { Image(systemName: "questionmark.circle") }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String.appLocalized("Getting Started"))
            }
            Picker(String.appLocalized("Settings Section"), selection: $selectedSection) {
                Text(String.appLocalized("General")).tag(SettingsSection.general)
                Text(String.appLocalized("Audio Settings")).tag(SettingsSection.audio)
                Text(String.appLocalized("Connection & Permissions")).tag(SettingsSection.connection)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("settingsSectionPicker")
            Group {
                switch selectedSection {
                case .general: generalSettings
                case .audio: audioSettings
                case .connection: connectionSettings
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(32)
        .frame(width: 620, height: 540)
        .background(AppTheme.canvas)
        .font(AppTypography.body)
        .foregroundStyle(AppTheme.ink).tint(AppTheme.teal)
        .background(SettingsWindowReader(language: settings.appLanguage))
        .sheet(isPresented: $showsGettingStarted) {
            VStack(alignment: .leading, spacing: 20) {
                Text(String.appLocalized("Getting Started")).font(AppTypography.section)
                Text(String.appLocalized("Pair the remote in Bluetooth settings. Choose the same virtual microphone in this app and your input method, then select the matching voice shortcut."))
                    .fixedSize(horizontal: false, vertical: true)
                Link(String.appLocalized("Install BlackHole 2ch…"), destination: URL(string: "https://existential.audio/blackhole/")!)
                Text(String.appLocalized("Audio stays on this Mac and is not recorded. WeChat Input handles speech recognition."))
                    .foregroundStyle(AppTheme.muted).fixedSize(horizontal: false, vertical: true)
                HStack { Spacer(); Button(String.appLocalized("Done")) { showsGettingStarted = false } }
            }
            .font(AppTypography.body).padding(28).frame(width: 480)
            .background(AppTheme.canvas)
        }
        .environment(\.locale, localization.locale)
        .onAppear { refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                SettingsField(title: String.appLocalized("Language")) {
                    Picker(String.appLocalized("Language"), selection: $settings.appLanguage) {
                        ForEach(AppLanguage.allCases) { Text(verbatim: $0.title).tag($0) }
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("appLanguagePicker")
                }
            }
            SectionRule()
            HStack {
                Text(String.appLocalized("Connect at Launch"))
                Spacer()
                Toggle(String.appLocalized("Connect at Launch"), isOn: $settings.connectAtLaunch)
                    .labelsHidden().toggleStyle(.switch)
                    .accessibilityIdentifier("connectAtLaunchToggle")
            }
            HStack {
                Text(String.appLocalized("Launch at Login"))
                Spacer()
                Toggle(String.appLocalized("Launch at Login"), isOn: Binding(get: { loginItem.isEnabled }, set: loginItem.setEnabled))
                    .labelsHidden().toggleStyle(.switch).accessibilityIdentifier("launchAtLoginToggle")
            }
            if loginItem.needsApproval {
                Button(String.appLocalized("Open Login Items Settings")) { loginItem.openSystemSettings() }
            }
            if let error = loginItem.errorMessage { Text(error.appTranslated).foregroundStyle(AppTheme.coral).font(AppTypography.caption) }
        }
    }

    private var audioSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(String.appLocalized("Audio Settings")).font(AppTypography.section)
            SettingsField(title: String.appLocalized("Virtual Microphone")) {
                Picker(String.appLocalized("Virtual Microphone"), selection: $outputUID) {
                    Text(String.appLocalized("Select a device")).tag("")
                    ForEach(model.outputs) { Text($0.name).tag($0.uid) }
                    if !outputUID.isEmpty && !deviceAvailable {
                        Text(String.appLocalized("Previously selected device unavailable")).tag(outputUID)
                    }
                }.labelsHidden()

            }
            HStack(spacing: 10) {
                Button(String.appLocalized("Refresh Devices")) { model.refreshDevices() }
                Button(String.appLocalized("Play Test Tone")) { model.playTestTone() }
                    .disabled(!deviceAvailable || hasChanges)
                    .help(hasChanges ? String.appLocalized("Apply your changes before testing.") : String.appLocalized("Play Test Tone"))
            }.padding(.leading, 196).controlSize(.small)
            SettingsField(title: String.appLocalized("Keep System Input")) {
                Toggle(String.appLocalized("Keep System Input"), isOn: $keepSystemInput)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .accessibilityIdentifier("keepSystemInputToggle")
                    .help(String.appLocalized("Keep the selected virtual microphone as system input while the remote is connected."))
            }
            SettingsField(title: String.appLocalized("WeChat Voice Shortcut")) {
                Picker(String.appLocalized("WeChat Voice Shortcut"), selection: $voiceKey) {
                    ForEach(VoiceKey.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
            }
            HStack {
                Label(status, systemImage: statusSymbol)
                    .font(AppTypography.caption).foregroundStyle(hasChanges ? AppTheme.coral : model.ready ? AppTheme.teal : AppTheme.muted)
                Spacer()
                if hasChanges {
                    Button(String.appLocalized("Revert")) { restoreSelection() }
                }
                Button(model.isConnected ? String.appLocalized("Apply Settings") : String.appLocalized("Save Settings")) {
                    settings.outputUID = outputUID
                    settings.voiceKey = voiceKey
                    settings.keepSystemInput = keepSystemInput
                    model.applySettings()
                }
                .buttonStyle(.borderedProminent)
                .disabled((!deviceAvailable && !onlyDisablingInputLock) || (!hasChanges && (!model.isConnected || model.ready)))
            }
            if !hasChanges, let testToneMessage = model.testToneMessage {
                Text(testToneMessage.appTranslated).font(AppTypography.caption).foregroundStyle(AppTheme.muted).fixedSize(horizontal: false, vertical: true)
            }
            if model.inputRestorationError != nil || (!model.ready && model.isConnected) {
                Text((model.statusMessage).appTranslated).font(AppTypography.caption).foregroundStyle(AppTheme.muted)
                    .lineLimit(3).help((model.statusMessage).appTranslated)
            } else if !model.isConnected {
                Text(String.appLocalized("Saved settings will be used when the remote connects."))
                    .font(AppTypography.caption).foregroundStyle(AppTheme.muted)
            }
        }.disabled(busy)
    }

    private var connectionSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String.appLocalized("Connection & Permissions")).font(AppTypography.section)
            HStack {
                Button(String.appLocalized("Bluetooth Settings")) { openSettings("com.apple.BluetoothSettings") }
                Button(String.appLocalized("Sound Settings")) { openSettings("com.apple.Sound-Settings.extension") }
                Button(String.appLocalized("Reconnect")) { model.reconnect() }.disabled(busy)
            }
            if !model.bluetoothAllowed {
                Button(String.appLocalized("Bluetooth Permission")) { openSettings("com.apple.preference.security?Privacy_Bluetooth") }
            }
            if !model.accessibilityAllowed {
                Button(String.appLocalized("Allow Accessibility")) { model.requestAccessibility() }
            }
            if !model.inputMonitoringAllowed {
                Button(String.appLocalized("Allow Input Monitoring")) { model.requestInputMonitoring() }
            }
        }
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
    @ObservedObject private var localization = AppLocalization.shared
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 16) {
            Text(title).font(AppTypography.body).frame(width: 180, alignment: .leading)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
