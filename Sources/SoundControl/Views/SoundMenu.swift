import SwiftUI
import SoundControlCore

/// Menu items listing every sound the app knows, grouped by source.
struct SoundCatalogItems: View {
    @Environment(AppModel.self) private var model
    let selected: Set<SoundRef>
    let onPick: (SoundRef) -> Void

    var body: some View {
        ForEach(BuiltInPack.allCases.filter { $0 != .system }, id: \.self) { pack in
            Menu {
                ForEach(Motif.allCases, id: \.self) { motif in
                    item(.synth(pack: pack, motif: motif, take: 0), title: motif.title)
                }
            } label: {
                Label(pack.title, systemImage: pack.symbol)
            }
        }
        Menu {
            ForEach(BuiltInPack.systemSoundNames, id: \.self) { name in
                item(.system(name: name), title: name)
            }
        } label: {
            Label(BuiltInPack.system.title, systemImage: BuiltInPack.system.symbol)
        }
        Menu {
            if model.config.userSounds.isEmpty {
                Text("No sounds yet — import some in My Sounds")
            }
            ForEach(model.config.userSounds) { sound in
                item(.user(id: sound.id), title: sound.name)
            }
        } label: {
            Label("My Sounds", systemImage: "waveform")
        }
    }

    private func item(_ ref: SoundRef, title: String) -> some View {
        Button {
            onPick(ref)
        } label: {
            if selected.contains(ref) {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}

/// Chip showing what a trigger plays, with a menu to pick a single sound or follow the pack.
struct TriggerSoundMenu: View {
    @Environment(AppModel.self) private var model
    let trigger: TriggerID

    var body: some View {
        let setting = model.config.setting(for: trigger)
        Menu {
            Button {
                model.setSounds([], for: trigger)
            } label: {
                if setting.followsPack {
                    Label("Follow pack", systemImage: "checkmark")
                } else {
                    Text("Follow pack")
                }
            }
            Divider()
            SoundCatalogItems(selected: Set(setting.customSounds)) { ref in
                model.setSounds([ref], for: trigger)
                model.preview(ref, volume: setting.volume)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: setting.followsPack ? "square.stack.3d.up.fill" : "music.note")
                Text(chipTitle(setting)).lineLimit(1)
            }
            .font(.caption.weight(.medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .foregroundStyle(Theme.accent)
        .help("Choose the sound for this trigger")
    }

    private func chipTitle(_ setting: TriggerSetting) -> String {
        let candidates = SoundResolver.candidates(for: trigger, in: model.config)
        guard let first = candidates.first else { return "No sound" }
        if setting.followsPack {
            return TriggerCatalog.info(for: trigger).motif.title
        }
        let name = SoundResolver.displayName(of: first, in: model.config)
        return candidates.count > 1 ? "\(name) +\(candidates.count - 1)" : name
    }
}
