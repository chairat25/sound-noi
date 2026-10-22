import AppKit
import SwiftUI
import SoundControlCore

/// The popover under the menu-bar icon: quick controls and the latest events.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    private static let recentCount = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "waveform.circle.fill").font(.title2).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Sound Control").font(.headline)
                    Text("\(model.config.enabledTriggers.count) triggers on").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { model.config.isListening },
                                         set: { value in model.update { $0.withListening(value) } }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(Theme.accent)
            }

            HStack {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                Slider(value: Binding(get: { model.config.masterVolume },
                                      set: { value in model.update { $0.withMasterVolume(value) } }), in: 0...1)
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
            }

            Picker("Pack", selection: Binding(get: { model.config.activePack },
                                              set: { value in model.update { $0.selectingPack(value) } })) {
                ForEach(BuiltInPack.allCases, id: \.self) { Text($0.title).tag(PackSelection.builtIn($0)) }
                if !model.config.customPacks.isEmpty {
                    Divider()
                    ForEach(model.config.customPacks) { Text($0.name).tag(PackSelection.custom($0.id)) }
                }
            }

            Divider()
            Text("RECENT").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            if model.log.entries.isEmpty {
                Text("No events yet").font(.callout).foregroundStyle(.tertiary)
            } else {
                ForEach(model.log.entries.prefix(Self.recentCount)) { entry in
                    ActivityRow(entry: entry, compact: true)
                }
            }
            Divider()

            HStack {
                Button("Open Sound Control…") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                .keyboardShortcut(",")
                Spacer()
                Button("Quit") {
                    model.flushSave()
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}
