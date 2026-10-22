import SwiftUI
import SoundControlCore

struct SettingsPage: View {
    @Environment(AppModel.self) private var model
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section("General") {
                Toggle("Listening", isOn: Binding(get: { model.config.isListening },
                                                  set: { value in model.update { $0.withListening(value) } }))
                LabeledContent("Master volume") {
                    HStack {
                        Slider(value: Binding(get: { model.config.masterVolume },
                                              set: { value in model.update { $0.withMasterVolume(value) } }), in: 0...1)
                        PlayButton { model.preview(.chargerConnected) }
                    }
                }
                Toggle("Launch at login", isOn: Binding(get: { model.isLaunchAtLoginEnabled },
                                                        set: { model.setLaunchAtLogin($0) }))
            }

            Section {
                Toggle("Instant sounds", isOn: Binding(get: { model.config.keepAudioReady },
                                                       set: { value in model.update { $0.withKeepAudioReady(value) } }))
                Toggle("One sound per moment", isOn: Binding(get: { model.config.avoidOverlap },
                                                             set: { value in model.update { $0.withAvoidOverlap(value) } }))
            } header: {
                Text("Responsiveness")
            } footer: {
                Text("Instant sounds keeps the audio output ready while you use the Mac and lets it rest when you step away, so the Mac still sleeps on its own. One sound per moment plays only the first of several events that happen together, such as wake + display on.")
            }

            Section {
                Toggle(isOn: Binding(get: { model.config.replaceMacSounds },
                                     set: { value in model.update { $0.withReplaceMacSounds(value) } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Replace macOS sounds")
                        Text("When a trigger is on, macOS's own sound for that moment is muted so only yours plays.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(MacSoundTweak.allCases.filter(\.isSound), id: \.self) { tweak in
                    LabeledContent {
                        Badge(text: model.config.isApplied(tweak) ? "Muted by Sound Control" : "macOS default",
                              color: model.config.isApplied(tweak) ? Theme.accent : .secondary)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tweak.title)
                            Text(tweak.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Toggle(isOn: Binding(get: { model.config.hideScreenshotThumbnail },
                                     set: { value in model.update { $0.withHideScreenshotThumbnail(value) } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hide floating screenshot thumbnail")
                        Text(MacSoundTweak.screenshotThumbnail.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("macOS sounds")
            } footer: {
                Text("macOS gets its sounds back when you turn the trigger off, pause listening, or quit Sound Control. Interface sound effects may need a log out to fully apply.")
            }

            Section {
                Toggle("Quiet hours", isOn: quietBinding(\.isEnabled))
                DatePicker("From", selection: minuteBinding(\.startMinute), displayedComponents: .hourAndMinute)
                    .disabled(!model.config.quietHours.isEnabled)
                DatePicker("Until", selection: minuteBinding(\.endMinute), displayedComponents: .hourAndMinute)
                    .disabled(!model.config.quietHours.isEnabled)
            } header: {
                Text("Quiet hours")
            } footer: {
                Text("Nothing plays during this window. It may cross midnight.")
            }

            Section("Thresholds") {
                Stepper("Battery low at \(model.config.batteryLowPercent)%", value: Binding(
                    get: { model.config.batteryLowPercent },
                    set: { value in model.update { $0.withBatteryThresholds(low: value, critical: $0.batteryCriticalPercent) } }
                ), in: AppConfig.batteryLowRange)
                Stepper("Battery critical at \(model.config.batteryCriticalPercent)%", value: Binding(
                    get: { model.config.batteryCriticalPercent },
                    set: { value in model.update { $0.withBatteryThresholds(low: $0.batteryLowPercent, critical: value) } }
                ), in: AppConfig.batteryCriticalRange)
                Stepper("Away after \(model.config.idleMinutes) min without input", value: Binding(
                    get: { model.config.idleMinutes },
                    set: { value in model.update { $0.withIdleMinutes(value) } }
                ), in: AppConfig.idleMinutesRange)
            }

            Section {
                LabeledContent("Input Monitoring") {
                    HStack {
                        Badge(text: model.hasInputPermission ? "Granted" : "Not granted",
                              color: model.hasInputPermission ? .green : Theme.warning)
                        Button("Open Settings") { PrivacySettings.openInputMonitoring() }
                        Button("Recheck") { model.recheckInputPermission() }
                    }
                }
                LabeledContent("Bluetooth") {
                    Button("Open Settings") { PrivacySettings.openBluetooth() }
                }
                LabeledContent("Full Disk Access (Trash trigger)") {
                    Button("Open Settings") { PrivacySettings.openFullDiskAccess() }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Keyboard & mouse triggers need Input Monitoring. Only key codes are checked — nothing you type is read or stored. After rebuilding the app you may need to grant it again.")
            }

            Section("Data") {
                Button("Show sounds folder") { model.revealSoundsFolder() }
                Button("Reset all settings…", role: .destructive) { confirmReset = true }
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
                LabeledContent("Triggers", value: "\(TriggerID.allCases.count)")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Reset all settings?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { model.resetAll() }
        } message: {
            Text("Triggers, packs and volumes go back to defaults. Your sound files stay on disk.")
        }
    }

    private func quietBinding(_ keyPath: WritableKeyPath<QuietHours, Bool>) -> Binding<Bool> {
        Binding(get: { model.config.quietHours[keyPath: keyPath] }, set: { value in
            var quiet = model.config.quietHours
            quiet[keyPath: keyPath] = value
            model.update { $0.withQuietHours(quiet) }
        })
    }

    private func minuteBinding(_ keyPath: WritableKeyPath<QuietHours, Int>) -> Binding<Date> {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return Binding(
            get: { startOfDay.addingTimeInterval(TimeInterval(model.config.quietHours[keyPath: keyPath] * 60)) },
            set: { date in
                var quiet = model.config.quietHours
                quiet[keyPath: keyPath] = PlaybackGate.minuteOfDay(date, calendar: .current)
                model.update { $0.withQuietHours(quiet) }
            }
        )
    }
}
