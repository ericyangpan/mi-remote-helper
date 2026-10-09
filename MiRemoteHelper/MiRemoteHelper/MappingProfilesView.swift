import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MappingProfilesView: View {
    @ObservedObject var model: ButtonMappingModel
    @State private var showingImport = false
    @State private var showingExport = false
    @State private var exportFile: MappingFile?
    @State private var exportName = "mi-remote-global"
    @State private var pendingImport: MappingDefinition?
    @State private var errorMessage: String?
    @State private var deletingApplication = false
    @State private var resetProfileID: String?

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Text(String(localized: "Edit Mappings")).foregroundStyle(AppTheme.muted)
                Picker(String(localized: "Edit Mappings"), selection: Binding(get: { model.selectedProfileID }, set: model.selectProfile)) {
                    Text(String(localized: "Global")).tag("global")
                    ForEach(model.applicationProfiles) { entry in Text(entry.definition.name).tag(entry.id) }
                }.labelsHidden().frame(width: 140, alignment: .leading)
            }.fixedSize()
            if let application = model.selectedApplication {
                Toggle(String(localized: "App Mapping"), isOn: Binding(
                    get: { application.enabled }, set: { model.setApplicationEnabled($0, profileID: application.id) }
                )).toggleStyle(.switch).controlSize(.small)
                    .help(application.definition.bundleIdentifier ?? "")
                    .fixedSize()
            }
            Spacer(minLength: 0)
            Button(action: addApplication) { Label(String(localized: "Add App…"), systemImage: "plus") }
                .accessibilityIdentifier("addMappingApp")
            Button(String(localized: "Import…")) { showingImport = true }
                .accessibilityIdentifier("importMapping")
            Button(String(localized: "Export…"), action: exportDefinition)
                .accessibilityIdentifier("exportMapping")
            Menu {
                Button(model.selectedProfileID == "global" ? String(localized: "Restore Defaults") : String(localized: "Inherit All Global Mappings")) { resetProfileID = model.selectedProfileID }
                if model.selectedApplication != nil {
                    Divider()
                    Button(String(localized: "Remove App Mapping…"), role: .destructive) { deletingApplication = true }
                }
            } label: {
                Image(systemName: "ellipsis").frame(width: 30, height: 30)
                    .background(AppTheme.paper, in: Circle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel(String(localized: "Mapping Actions"))
        }
        .font(AppTypography.compact)
        .controlSize(.small)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(AppTheme.mint, in: RoundedRectangle(cornerRadius: 16))
        .fileImporter(isPresented: $showingImport, allowedContentTypes: [.json]) { result in
            do { pendingImport = try MappingFile.read(result.get()) }
            catch { report(error) }
        }
        .fileExporter(isPresented: $showingExport, document: exportFile, contentType: .json, defaultFilename: exportName) { result in
            if case .failure(let error) = result { report(error) }
        }
        .sheet(item: $pendingImport) { definition in
            MappingImportPreview(definition: definition, onCancel: { pendingImport = nil }, onApply: {
                do { try model.importDefinition(definition); pendingImport = nil }
                catch { errorMessage = error.localizedDescription; pendingImport = nil }
            })
        }
        .alert(String(localized: "Mapping File"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(String(localized: "OK")) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .confirmationDialog(String(localized: "Reset these mappings?"), isPresented: Binding(get: { resetProfileID != nil }, set: { if !$0 { resetProfileID = nil } }), titleVisibility: .visible) {
            Button(String(localized: "Reset"), role: .destructive) {
                if let resetProfileID { model.reset(profileID: resetProfileID) }
                resetProfileID = nil
            }
            Button(String(localized: "Cancel"), role: .cancel) { resetProfileID = nil }
        } message: {
            Text(resetProfileID == "global"
                 ? String(localized: "This replaces your Global mappings with defaults. App mappings stay unchanged.")
                 : String(localized: "This removes this app’s overrides. All actions will inherit Global mappings."))
        }
        .confirmationDialog(String(localized: "Remove this app mapping?"), isPresented: $deletingApplication) {
            Button(String(localized: "Remove"), role: .destructive) { model.removeApplication(model.selectedProfileID) }
        } message: { Text(String(localized: "This app will use Global mappings. Your Global mappings will be kept.")) }
    }

    private func report(_ error: Error) {
        guard (error as NSError).code != NSUserCancelledError else { return }
        errorMessage = error.localizedDescription
    }

    private func exportDefinition() {
        do {
            let definition = try model.exportDefinition(profileID: model.selectedProfileID)
            exportFile = MappingFile(data: try MappingDefinitionCodec.encode(definition))
            exportName = "mi-remote-\(definition.bundleIdentifier ?? "global")"
            showingExport = true
        } catch { errorMessage = error.localizedDescription }
    }

    private func addApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { throw MappingDefinitionError.invalidDefinition }
                let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? url.deletingPathExtension().lastPathComponent
                try model.addApplication(name: name, bundleIdentifier: identifier)
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct MappingImportPreview: View {
    let definition: MappingDefinition
    let onCancel: () -> Void
    let onApply: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "Import Mapping Definition")).font(AppTypography.section)
            Text(definition.scope == .global ? String(localized: "Global") : definition.name).font(AppTypography.emphasis)
            if let identifier = definition.bundleIdentifier { Text(identifier).font(AppTypography.caption).foregroundStyle(.secondary) }
            Text(definition.scope == .global
                ? String(localized: "This replaces all Global short-press, double-press and long-press mappings. App mappings stay unchanged.")
                : String(localized: "This replaces the overrides for this app. Unlisted actions inherit Global mappings."))
                .font(AppTypography.body).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(RemoteButton.allCases.filter { $0 != .microphone }) { button in
                        ForEach(ButtonPressKind.allCases) { press in
                            if let binding = definition.override(for: button, press: press) {
                                HStack {
                                    Text("\(button.displayName) · \(press.title)")
                                    Spacer()
                                    Text(binding.displayName).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if definition.shortPress.isEmpty && definition.longPress.isEmpty && definition.doublePress.isEmpty {
                        Text(String(localized: "All actions inherit Global mappings."))
                    }
                }
            }.frame(maxHeight: 320)
            HStack {
                Spacer()
                Button(String(localized: "Cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Apply Import"), action: onApply).buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }.font(AppTypography.body).padding(24).frame(width: 570)
    }
}
