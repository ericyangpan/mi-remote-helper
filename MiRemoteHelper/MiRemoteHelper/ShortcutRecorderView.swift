import AppKit
import SwiftUI

struct ShortcutRecorderView: View {
    @ObservedObject private var localization = AppLocalization.shared
    let button: RemoteButton
    let press: ButtonPressKind
    let onCancel: () -> Void
    let onRecord: (KeyChord) -> Bool

    @State private var monitor: Any?
    @State private var pending: KeyChord?
    @State private var errorText = ""
    @State private var capturedKeyCode: UInt16?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(String.appLocalized("\(button.displayName) · \(press.title)"))
                .font(AppTypography.section)
            Text(pending == nil ? String.appLocalized("Press a key or key combination.") : String.appLocalized("Return to save · Esc to cancel"))
                .font(AppTypography.body).foregroundStyle(AppTheme.muted)

            VStack(spacing: 10) {
                if let pending {
                    Text(pending.displayName).font(AppTypography.recordedShortcut)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Label(String.appLocalized("Shortcut captured"), systemImage: "checkmark.circle")
                        .font(AppTypography.caption).foregroundStyle(AppTheme.teal)
                } else {
                    Image(systemName: "keyboard").font(.system(size: 26)).foregroundStyle(AppTheme.teal)
                        .accessibilityHidden(true)
                    Text(String.appLocalized("Waiting for input")).font(AppTypography.body).foregroundStyle(AppTheme.muted)
                }
            }
            .padding(.horizontal, 20).frame(maxWidth: .infinity).frame(height: 112)
            .background(AppTheme.mint, in: RoundedRectangle(cornerRadius: 14))

            if !errorText.isEmpty {
                Text((errorText).appTranslated)
                    .font(AppTypography.caption)
                    .foregroundColor(.red)
            }

            HStack {
                if pending != nil {
                    Button(String.appLocalized("Record Again")) { startMonitoring() }
                }
                Spacer()
                Button(String.appLocalized("Cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(String.appLocalized("Save")) {
                    if let pending, !onRecord(pending) { errorText = MappingDefinitionError.busy.localizedDescription }
                }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(pending == nil)
            }
        }
        .font(AppTypography.body)
        .padding(28)
        .frame(width: 480)
        .background(AppTheme.canvas).foregroundStyle(AppTheme.ink).tint(AppTheme.teal)
        .onAppear { startMonitoring() }
        .onDisappear { stopMonitoring() }
    }

    private func startMonitoring() {
        stopMonitoring()
        pending = nil
        capturedKeyCode = nil
        errorText = ""
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            guard event.getIntegerValueFieldIfSynthetic == nil else { return event }
            // Consume repeats until the recorded key is released, then restore normal dialog keys.
            if let capturedKeyCode {
                if event.type == .keyUp, event.keyCode == capturedKeyCode { stopMonitoring() }
                return nil
            }
            guard event.type == .keyDown else { return event }
            guard !event.isARepeat else { return nil }
            if event.keyCode == 53, event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
                onCancel()
                return nil
            }
            guard let chord = KeyChord.from(event: event) else {
                errorText = String.appStatus("Choose a standard key or function key.")
                return nil
            }
            errorText = ""
            pending = chord
            capturedKeyCode = event.keyCode
            return nil
        }
    }

    private func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

private extension NSEvent {
    var getIntegerValueFieldIfSynthetic: Int64? {
        guard let cgEvent else { return nil }
        let marker = cgEvent.getIntegerValueField(.eventSourceUserData)
        return [KeyboardInjector.syntheticEventMarker, VoiceEventDiagnostics.marker].contains(marker) ? marker : nil
    }
}

extension KeyChord {
    static func from(event: NSEvent) -> Self? {
        guard event.type == .keyDown,
              let label = label(for: event)
        else { return nil }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return Self(keyCode: event.keyCode, keyLabel: label, modifiers: modifiers)
    }

    private static func label(for event: NSEvent) -> String? {
        let fixed: [UInt16: String] = [
            36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape",
            76: "Enter", 115: "Home", 116: "Page Up", 117: "Forward Delete",
            119: "End", 121: "Page Down", 123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18",
            80: "F19", 90: "F20",
        ]
        if let label = fixed[event.keyCode] { return label }
        guard let characters = event.charactersIgnoringModifiers,
              characters.count == 1,
              let scalar = characters.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar)
        else { return nil }
        return characters.uppercased()
    }
}
