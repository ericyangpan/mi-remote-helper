import SwiftUI

struct MainWindowView: View {
    @ObservedObject private var localization = AppLocalization.shared
    @ObservedObject var model: BridgeModel
    @SceneStorage("mainDestination") private var destination = "voice"
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 210)
            Group {
                if destination == "mapping" {
                    ButtonMappingsView(bridge: model, model: model.buttons)
                } else {
                    ContentView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.canvas)
        }
        .font(AppTypography.body)
        .foregroundStyle(AppTheme.ink).tint(AppTheme.teal)
        .frame(width: 1180, height: 800)
        .background(MainWindowReader())
        .onAppear { MainWindowPlacement.shared.openMainWindow = { openWindow(id: "main") } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshDevices(); model.refreshPermissions() }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().scaledToFit().frame(width: 42, height: 42)
                    .accessibilityHidden(true)
                Text("Mi Remote\nHelper").fixedSize(horizontal: true, vertical: false).font(AppTypography.brand)
            }.padding(.bottom, 32)
            VStack(alignment: .leading, spacing: 12) {
                Text("Xiaomi 2 Pro").font(AppTypography.label)
                HStack(spacing: 7) {
                    Circle().fill(model.isConnected ? AppTheme.teal : AppTheme.muted).frame(width: 6, height: 6)
                    Text(model.isConnected ? String.appLocalized("Connected") : model.state.displayText)
                        .font(AppTypography.caption).foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    RemoteBatteryView(level: model.batteryLevel, charging: model.batteryCharging, connected: model.isConnected).fixedSize()
                }
                .frame(height: 30, alignment: .leading)
                if !model.isRunning {
                    Button(String.appLocalized("Connect Remote")) { model.start() }
                        .buttonStyle(.borderedProminent).tint(AppTheme.coral)
                        .controlSize(.small).accessibilityIdentifier("connectButton")
                } else {
                    HStack(spacing: 8) {
                        Button(String.appLocalized("Disconnect")) { model.stop() }
                            .accessibilityIdentifier("disconnectButton")
                        Button { model.reconnect() } label: { Image(systemName: "arrow.clockwise") }
                            .help(String.appLocalized("Reconnect")).accessibilityLabel(String.appLocalized("Reconnect"))
                            .disabled(model.isSpeaking || model.isVoiceKeyHeld || model.testToneActive)
                    }.controlSize(.small)
                }
            }
            .padding(.bottom, 28)
            SectionRule().padding(.bottom, 16)
            navigation(String.appLocalized("Voice Input"), symbol: "mic", id: "voice")
            navigation(String.appLocalized("Button Mapping"), symbol: "square.grid.2x2", id: "mapping")
            Spacer(minLength: 30)
            CenteredSettingsLink {
                sidebarLabel(String.appLocalized("Settings"), symbol: "slider.horizontal.3")
            }.buttonStyle(.plain).accessibilityIdentifier("openSettings")
            Button { openWindow(id: "about") } label: {
                sidebarLabel(String.appLocalized("About"), symbol: "info.circle")
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 24).padding(.top, 30).padding(.bottom, 22)
        .frame(maxHeight: .infinity)
        .background(AppTheme.sidebar.ignoresSafeArea())
    }

    private func sidebarLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol).font(.system(size: 18)).frame(width: 24)
            Text(title).font(AppTypography.body)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12).contentShape(Rectangle())
    }

    private func navigation(_ title: String, symbol: String, id: String) -> some View {
        Button { destination = id } label: {
            HStack(spacing: 11) {
                Image(systemName: symbol).font(.system(size: 18)).frame(width: 24)
                Text(title).font(destination == id ? AppTypography.emphasis : AppTypography.body)
                Spacer(minLength: 0)
            }
            .foregroundStyle(destination == id ? AppTheme.ink : AppTheme.muted)
            .padding(.vertical, 15)
            .overlay(alignment: .leading) {
                if destination == id { Circle().fill(AppTheme.coral).frame(width: 6, height: 6).offset(x: -14) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("navigation_\(id)")
        .accessibilityAddTraits(destination == id ? .isSelected : [])
    }
}
