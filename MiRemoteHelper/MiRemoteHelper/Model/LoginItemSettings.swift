import Combine
import ServiceManagement

@MainActor
final class LoginItemSettings: ObservableObject {
    @Published private(set) var status = SMAppService.mainApp.status
    @Published private(set) var errorMessage: String?

    // A pending registration stays on, with a separate approval message.
    var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }

    func refresh() { status = SMAppService.mainApp.status }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        refresh()
        guard enabled != isEnabled else { return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            errorMessage = String.appStatus("Unable to change launch at login: \(error.localizedDescription)")
        }
        // Always read the system result; a local preference cannot prove that
        // macOS registered, approved or removed the login item.
        refresh()
        if enabled && needsApproval { errorMessage = nil }
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
