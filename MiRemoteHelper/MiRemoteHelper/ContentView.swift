import SwiftUI

struct ContentView: View {
    @ObservedObject var model: BridgeModel
    @ObservedObject private var settings: AppSettings

    init(model: BridgeModel) { self.model = model; settings = model.settings }
    private var busy: Bool { model.isSpeaking || model.isVoiceKeyHeld || model.testToneActive }
    private var deviceName: String { model.outputs.first { $0.uid == (model.ready ? model.activeOutputUID : settings.outputUID) }?.name ?? String(localized: "Select a device") }

    var body: some View {
        WorkspacePage(controlsHeight: 32) {
            Text(String(localized: "Voice Input")).font(AppTypography.heading)
                .accessibilityIdentifier("mainHeading")
        } controls: {
            contextBar
        } content: {
            HStack(alignment: .top, spacing: WorkspaceLayout.columnSpacing) {
                VStack(alignment: .leading, spacing: 30) {
                    HStack(alignment: .top, spacing: 28) {
                        metric(String(localized: "Input Level"), value: model.peakDBFS.map { String(format: "%.0f", $0) } ?? "—", unit: "dBFS")
                            .accessibilityIdentifier("inputLevel")
                        metric(String(localized: "This Session"), value: String(format: "%02d:%02d", Int(model.audioSeconds) / 60, Int(model.audioSeconds) % 60), unit: nil)
                    }
                    VStack(alignment: .leading, spacing: 20) {
                        Text(String(localized: "Audio")).font(AppTypography.section)
                        AudioMeterView(level: model.level, overloaded: model.audioOverloaded)
                            .frame(height: 28)
                    }
                    .padding(.vertical, 8)
                    .frame(maxHeight: .infinity)
                    voiceControls
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                RemotePhotoView(pressed: model.isVoiceKeyHeld || model.isSpeaking ? [.microphone] : [])
                    .frame(width: WorkspaceLayout.photoWidth)
            }
        } footer: {
            SettingsLink {
                HStack(spacing: 12) {
                    Image(systemName: "slider.horizontal.3").frame(width: 20)
                    Text(String(localized: "Audio Settings")).font(AppTypography.label)
                    Spacer(minLength: 12)
                    Text("\(deviceName) · \((model.ready ? model.activeVoiceKey : settings.voiceKey).title)")
                        .font(AppTypography.compact).foregroundStyle(AppTheme.muted).lineLimit(1)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .medium))
                }.frame(maxWidth: .infinity, minHeight: 30).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("audioSettings")
        }
    }

    private var contextBar: some View {
        HStack(spacing: 16) {
            if !model.ready || model.audioOverloaded || model.inputRestorationError != nil {
                Label(model.audioOverloaded ? String(localized: "Input overloaded. Lower the microphone gain.") : model.statusMessage,
                      systemImage: model.audioOverloaded ? "exclamationmark.triangle" : "info.circle")
                    .font(AppTypography.compact).foregroundStyle(model.audioOverloaded ? AppTheme.coral : AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("bridgeStatus")
                Spacer(minLength: 0)
                if !model.ready { SettingsLink { Text(String(localized: "Set Up…")) } }
            } else {
                Text(String(localized: "Hold the voice button to speak")).foregroundStyle(AppTheme.muted)
                Spacer()
                HStack(spacing: 7) {
                    Circle().fill(AppTheme.teal).frame(width: 6, height: 6)
                    Text(model.isSpeaking ? String(localized: "Receiving Audio") : String(localized: "Ready"))
                        .font(AppTypography.compact).foregroundStyle(AppTheme.teal)
                }
            }
        }
    }

    private var voiceControls: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 20) {
                Text(String(localized: "Speaking Mode")).font(AppTypography.section)
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    modeButton(String(localized: "Normal"), whisper: false)
                    modeButton(String(localized: "Whisper"), whisper: true)
                }
                .padding(3).frame(width: 200).background(AppTheme.paper, in: Capsule())
            }
            Rectangle().fill(AppTheme.teal.opacity(0.15)).frame(height: 1).accessibilityHidden(true)
            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(settings.whisperMode ? String(localized: "Whisper Gain") : String(localized: "Microphone Gain"))
                        .font(AppTypography.label)
                    Spacer()
                    Text(String(format: "%+.0f dB", settings.activeGainDB))
                        .font(AppTypography.gain).monospacedDigit().accessibilityIdentifier("gainValue")
                }
                Slider(value: Binding(get: { settings.activeGainDB }, set: { settings.activeGainDB = $0 }), in: -6...18, step: 1)
                    .tint(AppTheme.teal).accessibilityLabel(String(localized: "Microphone Gain"))
                HStack { Text("−6"); Spacer(); Text("+18") }.font(AppTypography.caption).foregroundStyle(AppTheme.muted)
            }
        }
        .padding(24).background(AppTheme.mint, in: RoundedRectangle(cornerRadius: 18))
        .disabled(busy)
    }

    private func modeButton(_ title: String, whisper: Bool) -> some View {
        Button { settings.whisperMode = whisper } label: {
            Text(title).font(AppTypography.label).frame(maxWidth: .infinity).padding(.vertical, 9)
                .foregroundStyle(settings.whisperMode == whisper ? AppTheme.canvas : AppTheme.muted)
                .background(settings.whisperMode == whisper ? AppTheme.coral : .clear, in: Capsule())
                .contentShape(Capsule())
        }.buttonStyle(.plain)
            .accessibilityIdentifier(whisper ? "whisperMode" : "normalMode")
            .accessibilityAddTraits(settings.whisperMode == whisper ? .isSelected : [])
    }

    private func metric(_ title: String, value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(AppTypography.body).foregroundStyle(AppTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 10).overlay(alignment: .bottom) { SectionRule() }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value).font(AppTypography.metric).monospacedDigit()
                if let unit { Text(unit).font(AppTypography.label) }
            }.lineLimit(1).minimumScaleFactor(0.8)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AudioMeterView: View {
    let level: Double
    let overloaded: Bool
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<48) { index in
                Capsule().fill(Double(index) / 48 < level ? (overloaded ? AppTheme.coral : AppTheme.teal) : AppTheme.rule)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Remote audio level"))
        .accessibilityValue(Text("\(Int(level * 100))%"))
    }
}
