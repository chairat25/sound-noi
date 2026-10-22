import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SoundControlCore

struct MySoundsPage: View {
    @Environment(AppModel.self) private var model
    @State private var isDropTargeted = false
    @State private var renaming: UserSound?
    @State private var newName = ""
    @State private var pendingDelete: UserSound?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "My Sounds",
                           subtitle: "Bring your own clips — WAV, AIFF, MP3, M4A, CAF or FLAC, up to 30 seconds.") {
                    HStack {
                        Button { model.revealSoundsFolder() } label: { Label("Show in Finder", systemImage: "folder") }
                        Button { chooseFiles() } label: { Label("Import…", systemImage: "plus") }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.accent)
                    }
                }
                dropZone
                if !model.config.userSounds.isEmpty {
                    Card {
                        ForEach(Array(model.config.userSounds.enumerated()), id: \.element.id) { index, sound in
                            if index > 0 { Divider().padding(.leading, 60) }
                            row(sound)
                        }
                    }
                }
            }
            .padding(24)
        }
        .alert("Rename sound", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let sound = renaming { model.renameSound(sound.id, to: newName) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("Delete “\(pendingDelete?.name ?? "")”?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Delete sound", role: .destructive) {
                if let sound = pendingDelete { model.deleteSound(sound.id) }
                pendingDelete = nil
            }
        } message: {
            Text("Triggers and packs using it will fall back to their pack sound.")
        }
    }

    private var dropZone: some View {
        VStack(spacing: 6) {
            Image(systemName: "waveform.badge.plus").font(.system(size: 30)).foregroundStyle(Theme.accent)
            Text("Drop audio files here").font(.headline)
            Text("Sounds are copied into Sound Control, so moving the originals is fine.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .background(isDropTargeted ? Theme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
            .foregroundStyle(isDropTargeted ? Theme.accent : Color.secondary.opacity(0.4)))
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            loadDropped(providers)
            return true
        }
    }

    private func row(_ sound: UserSound) -> some View {
        let usage = usageCount(sound.id)
        return HStack(spacing: 12) {
            SymbolTile(symbol: "waveform")
            VStack(alignment: .leading, spacing: 2) {
                Text(sound.name).font(.body.weight(.medium))
                Text("\(sound.duration.formatted(.number.precision(.fractionLength(1)))) s · used by \(usage) trigger\(usage == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            PlayButton { model.preview(.user(id: sound.id)) }
            Menu {
                Button("Rename…") {
                    newName = sound.name
                    renaming = sound
                }
                Divider()
                Button("Delete…", role: .destructive) { pendingDelete = sound }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .rowPadding()
    }

    private func usageCount(_ id: UUID) -> Int {
        let ref = SoundRef.user(id: id)
        let direct = model.config.triggers.values.filter { $0.customSounds.contains(ref) }.count
        let inPacks = model.config.customPacks.flatMap { $0.overrides.values }.filter { $0.contains(ref) }.count
        return direct + inPacks
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio]
        guard panel.runModal() == .OK else { return }
        model.importSounds(panel.urls)
    }

    private func loadDropped(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { _ = model.importSounds([url]) }
                }
            }
        }
    }
}
