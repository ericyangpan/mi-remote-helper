import SwiftUI

struct MappingActionPicker: View {
    @ObservedObject private var localization = AppLocalization.shared
    @ObservedObject var model: ButtonMappingModel
    let button: RemoteButton
    let press: ButtonPressKind
    let profileID: String
    let dismiss: () -> Void
    let record: () -> Void
    @State private var search = ""
    @State private var errorMessage: String?

    private var binding: ButtonBinding { model.binding(for: button, press: press, profileID: profileID) }
    private var inherited: Bool { model.inheritsGlobal(button, press: press, profileID: profileID) }
    private var isCustomShortcut: Bool { if case .shortcut = binding { return true }; return false }
    private var actions: [ButtonAction] {
        ButtonAction.allCases.filter { $0.matchesSearch(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String.appLocalized("\(button.displayName) · \(press.title)")).font(AppTypography.emphasis)
            TextField(String.appLocalized("Search actions"), text: $search)
                .textFieldStyle(.roundedBorder).accessibilityIdentifier("actionSearch")
            if profileID != "global" {
                Button {
                    guard model.canEdit(), model.pressed.isEmpty else { errorMessage = MappingDefinitionError.busy.localizedDescription; return }
                    model.inheritGlobal(button, press: press, profileID: profileID)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.triangle.branch").frame(width: 20)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(String.appLocalized("Use Global Mapping"))
                            Text(model.binding(for: button, press: press).displayName).font(AppTypography.caption).foregroundStyle(AppTheme.muted)
                        }
                        Spacer()
                        if inherited { Image(systemName: "checkmark") }
                    }.padding(8).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("inheritGlobalAction")
                SectionRule()
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(actions) { action in
                            Button {
                                if model.setBinding(.preset(action), for: button, press: press, profileID: profileID) { dismiss() }
                                else { errorMessage = MappingDefinitionError.busy.localizedDescription }
                            } label: {
                                HStack(spacing: 10) {
                                    MappingActionIcon(binding: .preset(action)).frame(width: 20)
                                    Text(action.displayName).frame(maxWidth: .infinity, alignment: .leading)
                                    if let key = action.keyLabel, !action.displayName.localizedStandardContains(key) {
                                        Text(verbatim: key).font(AppTypography.shortcut).foregroundStyle(AppTheme.muted)
                                    }
                                    if !inherited && binding == .preset(action) { Image(systemName: "checkmark") }
                                }.padding(8).contentShape(Rectangle())
                            }
                            .buttonStyle(ActionChoiceStyle(selected: !inherited && binding == .preset(action)))
                            .accessibilityIdentifier("action_\(action.rawValue)")
                            .id(action.rawValue)
                        }
                        if actions.isEmpty { Text(String.appLocalized("No matching actions")).foregroundStyle(AppTheme.muted).padding() }
                    }
                }
                .frame(height: 280).scrollIndicators(.visible)
                .onAppear {
                    if !inherited, case .preset(let action) = binding { proxy.scrollTo(action.rawValue, anchor: .center) }
                }
                .onChange(of: search) { _, _ in
                    if let first = actions.first { proxy.scrollTo(first.rawValue, anchor: .top) }
                }
            }
            SectionRule()
            Button(action: record) {
                HStack(spacing: 10) {
                    Image(systemName: "keyboard").frame(width: 20)
                    Text(String.appLocalized("Custom Shortcut…"))
                    Spacer(minLength: 8)
                    if case .shortcut(let chord) = binding, !inherited {
                        Text(chord.displayName).font(AppTypography.shortcut).foregroundStyle(AppTheme.teal)
                            .lineLimit(1).help(chord.displayName)
                    }
                }.padding(8).contentShape(Rectangle())
            }
            .buttonStyle(ActionChoiceStyle(selected: !inherited && isCustomShortcut))
            .accessibilityIdentifier("customShortcutAction")
            if let errorMessage { Text(errorMessage.appTranslated).font(AppTypography.caption).foregroundStyle(AppTheme.coral) }
        }
        .font(AppTypography.body)
        .padding(16).frame(width: 320).foregroundStyle(AppTheme.ink).tint(AppTheme.teal)
    }
}

private struct ActionChoiceStyle: ButtonStyle {
    let selected: Bool
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(selected ? AppTheme.mint : hovering || configuration.isPressed ? AppTheme.sidebar : .clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .onHover { hovering = $0 }
    }
}

struct MappingActionIcon: View {
    @ObservedObject private var localization = AppLocalization.shared
    let binding: ButtonBinding
    var body: some View {
        switch binding {
        case .preset(.showDesktop): Image("ShowDesktop")
        case .preset(let action): Image(systemName: action.symbolName)
        case .shortcut: Image(systemName: "keyboard")
        case .dictation: Image(systemName: "mic")
        }
    }
}

extension ButtonBinding {
    var compactName: String {
        switch self {
        case .preset(.contextMenu): return String.appLocalized("Context Menu")
        case .preset(.deleteBackward): return String.appLocalized("Backspace")
        default: return displayName
        }
    }
}
