import SwiftUI
import SoundControlCore

/// Full control over one trigger: its sound list, rotation, and volume.
struct TriggerDetailSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let trigger: TriggerID

    var body: some View {
        let info = TriggerCatalog.info(for: trigger)
        let setting = model.config.setting(for: trigger)
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                SymbolTile(symbol: info.symbol, isActive: setting.isEnabled, size: 44)
                VStack(alignment: .leading) {
                    Text(info.title).font(.title2.weight(.semibold))
                    Text(info.detail).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("On", isOn: Binding(get: { setting.isEnabled }, set: { model.setTrigger(trigger, enabled: $0) }))
                    .toggleStyle(.switch)
                    .tint(Theme.accent)
            }

            Picker("Sound source", selection: Binding(
                get: { setting.followsPack },
                set: { follow in
                    model.setSounds(follow ? [] : SoundResolver.candidates(for: trigger, in: model.config), for: trigger)
                }
            )) {
                Text("Follow pack (\(SoundResolver.packName(model.config.activePack, in: model.config)))").tag(true)
                Text("My own sounds").tag(false)
            }
            .pickerStyle(.radioGroup)

            soundList(setting: setting)

            HStack(spacing: 20) {
                Picker("Playback", selection: Binding(
                    get: { setting.playback },
                    set: { mode in model.update { $0.updatingTrigger(trigger) { $0.withPlayback(mode) } } }
                )) {
                    ForEach(PlaybackMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .frame(width: 240)
                HStack {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { setting.volume },
                        set: { volume in model.update { $0.updatingTrigger(trigger) { $0.withVolume(volume) } } }
                    ), in: 0...1)
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                }
            }

            HStack {
                Button {
                    model.preview(trigger)
                } label: {
                    Label("Test trigger", systemImage: "play.fill")
                }
                Text("Cooldown \(info.cooldown.formatted()) s").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    @ViewBuilder
    private func soundList(setting: TriggerSetting) -> some View {
        let candidates = SoundResolver.candidates(for: trigger, in: model.config)
        Card {
            if candidates.isEmpty {
                Text("No sounds yet. Add one below.").foregroundStyle(.secondary).rowPadding()
            }
            ForEach(Array(candidates.enumerated()), id: \.offset) { index, ref in
                if index > 0 { Divider() }
                HStack {
                    Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary).frame(width: 16)
                    Text(SoundResolver.displayName(of: ref, in: model.config))
                    Spacer()
                    PlayButton { model.preview(ref, volume: setting.volume) }
                    if !setting.followsPack {
                        Button {
                            model.setSounds(setting.customSounds.enumerated().filter { $0.offset != index }.map(\.element), for: trigger)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Remove")
                    }
                }
                .rowPadding()
            }
        }
        if !setting.followsPack {
            Menu {
                SoundCatalogItems(selected: Set(setting.customSounds)) { ref in
                    model.setSounds(setting.customSounds + [ref], for: trigger)
                    model.preview(ref, volume: setting.volume)
                }
            } label: {
                Label("Add sound", systemImage: "plus")
            }
            .fixedSize()
            Text("Add several sounds to rotate or shuffle between them each time the trigger fires.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
