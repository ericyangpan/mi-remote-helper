import SwiftUI

struct ButtonMappingsView: View {
    @ObservedObject private var localization = AppLocalization.shared
    @ObservedObject var bridge: BridgeModel
    @ObservedObject var model: ButtonMappingModel
    private struct RecordingTarget: Identifiable {
        let button: RemoteButton
        let press: ButtonPressKind
        let profileID: String
        var id: String { "\(profileID)_\(button.rawValue)_\(press.rawValue)" }
    }
    @State private var recordingTarget: RecordingTarget?
    @State private var showingHelp = false
    @Environment(\.scenePhase) private var scenePhase
    private var busy: Bool { bridge.isSpeaking || bridge.isVoiceKeyHeld || bridge.testToneActive || !model.pressed.isEmpty }

    var body: some View {
        WorkspacePage {
            HStack {
                Text(String.appLocalized("Button Mapping")).font(AppTypography.heading)
                Spacer()
                Toggle(String.appLocalized("Enable Button Mapping"), isOn: Binding(get: { model.enabled }, set: model.setEnabled))
                    .toggleStyle(.switch).controlSize(.small).font(AppTypography.body).disabled(busy)
                    .help(String.appLocalized("Enable Button Mapping"))
            }
        } controls: {
            MappingProfilesView(model: model).disabled(busy)
        } content: {
            VStack(spacing: 16) {
                if !model.active {
                    HStack(spacing: 10) {
                        Label((model.status).appTranslated, systemImage: "info.circle").font(AppTypography.body).foregroundStyle(AppTheme.muted)
                        Spacer(minLength: 0)
                        if !bridge.inputMonitoringAllowed {
                            Button(String.appLocalized("Allow Input Monitoring")) { bridge.requestInputMonitoring() }
                        }
                        if !bridge.accessibilityAllowed {
                            Button(String.appLocalized("Allow Accessibility")) { bridge.requestAccessibility() }
                        }
                    }.controlSize(.small)
                }
                HStack(alignment: .top, spacing: WorkspaceLayout.columnSpacing) {
                    mappingTable
                    RemotePhotoView(pressed: model.pressed.union(bridge.isVoiceKeyHeld ? [.microphone] : []), shortPressed: model.shortPressed, longPressed: model.longPressed, doublePressed: model.doublePressed)
                        .frame(width: WorkspaceLayout.photoWidth)
                }.frame(maxHeight: .infinity, alignment: .top)
            }
        } footer: {
            HStack {
                Text(model.active ? String.appLocalized("Active mapping: \(model.activeProfileName)") : model.status)
                    .font(AppTypography.caption).foregroundStyle(AppTheme.muted)
                Spacer()
                Button { showingHelp.toggle() } label: { Image(systemName: "questionmark") }
                    .buttonStyle(QuietIconButton()).help(String.appLocalized("Mapping Help"))
                    .popover(isPresented: $showingHelp) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(String.appLocalized("Mapping Help")).font(AppTypography.section)
                            Text(String.appLocalized("Overrides apply only when this app is in front. Other actions inherit Global mappings."))
                            Text(String.appLocalized("Hold for 0.5 seconds for a long press. When a double-press action is assigned, short presses wait 0.3 seconds for a second press. Voice input stays fixed."))
                            Text(String.appLocalized("In the app switcher, use Left/Right to choose, OK or Home to confirm, and Back to cancel."))
                        }.font(AppTypography.body).padding(24).frame(width: 340)
                    }
            }
        }
        .sheet(item: $recordingTarget, onDismiss: { model.recording = false }) { target in
            ShortcutRecorderView(button: target.button, press: target.press, onCancel: { recordingTarget = nil }, onRecord: {
                guard model.setBinding(.shortcut($0), for: target.button, press: target.press, profileID: target.profileID) else { return false }
                recordingTarget = nil
                return true
            }).onAppear { model.recording = true }
        }
        .onAppear { bridge.refreshPermissions(); model.refresh(connected: bridge.isConnected) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { bridge.refreshPermissions(); model.refresh(connected: bridge.isConnected) }
        }
    }

    private var mappingTable: some View {
        GeometryReader { geometry in
            let nameWidth: CGFloat = 116
            let cellWidth = max(80, (geometry.size.width - nameWidth - 36) / 3)
            let rowHeight = max(36, (geometry.size.height - 32) / CGFloat(RemoteButton.allCases.count))
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text(String.appLocalized("Button")).frame(width: nameWidth, alignment: .leading)
                    ForEach(ButtonPressKind.allCases) { Text($0.title).frame(width: cellWidth - 14, alignment: .leading).padding(.horizontal, 7) }
                }.font(AppTypography.caption).foregroundStyle(AppTheme.muted).padding(.horizontal, 6).frame(height: 31, alignment: .top)
                SectionRule()
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(RemoteButton.allCases) { button in
                            HStack(spacing: 8) {
                                HStack(spacing: 8) {
                                    RemoteButtonIcon(button: button).font(.system(size: 14, weight: .medium)).frame(width: 18)
                                        .foregroundStyle(feedbackColor(for: button) ?? AppTheme.ink)
                                    Text(button.displayName).font(AppTypography.compactMedium).lineLimit(1)
                                }.frame(width: nameWidth, alignment: .leading)
                                ForEach(ButtonPressKind.allCases) { press in
                                    if MappingDefinition.isConfigurable(button, press: press) {
                                        MappingActionCell(model: model, button: button, press: press, width: cellWidth) {
                                            recordingTarget = RecordingTarget(button: button, press: press, profileID: model.selectedProfileID)
                                        }
                                    } else {
                                        Label(button.defaultBinding(for: press).displayName, systemImage: "lock")
                                            .font(AppTypography.compact).foregroundStyle(AppTheme.muted)
                                            .frame(width: cellWidth, alignment: .leading)
                                    }
                                }
                            }
                            .padding(.horizontal, 6).frame(height: rowHeight - 1)
                            SectionRule()
                        }
                    }.disabled(busy)
                }
            }
        }.frame(maxWidth: .infinity)
    }

    private func feedbackColor(for button: RemoteButton) -> Color? {
        if model.longPressed.contains(button) { return .orange }
        if model.doublePressed.contains(button) { return .purple }
        if model.shortPressed.contains(button) || model.pressed.contains(button) || (button == .microphone && bridge.isVoiceKeyHeld) { return .blue }
        return nil
    }
}

private struct MappingActionCell: View {
    @ObservedObject private var localization = AppLocalization.shared
    @ObservedObject var model: ButtonMappingModel
    let button: RemoteButton
    let press: ButtonPressKind
    let width: CGFloat
    let record: () -> Void
    @State private var showingActions = false
    @State private var hovering = false
    private var binding: ButtonBinding { model.binding(for: button, press: press, profileID: model.selectedProfileID) }
    private var inherited: Bool { model.inheritsGlobal(button, press: press, profileID: model.selectedProfileID) }
    private var color: Color { press == .hold ? .orange : press == .doubleTap ? .purple : .blue }
    private var active: Bool { model.feedbackKind(for: button) == press }
    private var textFont: Font {
        if case .shortcut = binding { return AppTypography.shortcut }
        return AppTypography.compact
    }

    var body: some View {
        Button { showingActions = true } label: {
            HStack(spacing: 5) {
                MappingActionIcon(binding: binding).font(.system(size: 11)).frame(width: 14)
                Text(binding.compactName).font(textFont).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                Image(systemName: inherited ? "arrow.triangle.branch" : "chevron.down")
                    .font(.system(size: 8)).foregroundStyle(AppTheme.muted)
            }
            .foregroundStyle(active ? color : binding.isDisabled ? AppTheme.muted : AppTheme.ink)
            .padding(.horizontal, 7).frame(width: width, height: 29, alignment: .leading)
            .background(active ? color.opacity(0.10) : hovering ? AppTheme.sidebar.opacity(0.7) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(active ? color : hovering ? AppTheme.rule : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(inherited ? String.appLocalized("Inherit Global: \(binding.displayName)") : binding.displayName)
        .accessibilityLabel(String.appLocalized("\(button.displayName) · \(press.title)"))
        .accessibilityValue(binding.displayName)
        .accessibilityIdentifier("mapping_\(button.rawValue)_\(press.rawValue)")
        .popover(isPresented: $showingActions) {
            MappingActionPicker(model: model, button: button, press: press, profileID: model.selectedProfileID,
                dismiss: { showingActions = false }, record: {
                    showingActions = false
                    record()
                })
        }
    }
}
