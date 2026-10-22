import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SoundControlCore

struct PacksPage: View {
    @Environment(AppModel.self) private var model
    @State private var editingPack: UUID?
    @State private var pendingDelete: CustomPack?

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "Sound Packs",
                           subtitle: "A pack voices every trigger that follows it. Build your own to run the show.") {
                    HStack {
                        Button { importPack() } label: { Label("Import…", systemImage: "square.and.arrow.down") }
                        Menu {
                            ForEach(BuiltInPack.allCases, id: \.self) { base in
                                Button("Start from \(base.title)") { editingPack = model.createPack(from: base).id }
                            }
                        } label: {
                            Label("New pack", systemImage: "plus")
                        }
                        .fixedSize()
                    }
                }

                Text("BUILT IN").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(BuiltInPack.allCases, id: \.self) { pack in
                        BuiltInPackCard(pack: pack)
                    }
                }

                HStack {
                    Text("YOUR PACKS").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Text("· you are the game master").font(.caption).foregroundStyle(.tertiary)
                }
                if model.config.customPacks.isEmpty {
                    Card {
                        VStack(spacing: 8) {
                            Image(systemName: "theatermasks.fill").font(.largeTitle).foregroundStyle(Theme.accent)
                            Text("No custom packs yet").font(.headline)
                            Text("Start from any built-in pack, then swap in your own sounds trigger by trigger.")
                                .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(28)
                    }
                } else {
                    Card {
                        ForEach(Array(model.config.customPacks.enumerated()), id: \.element.id) { index, pack in
                            if index > 0 { Divider().padding(.leading, 60) }
                            customRow(pack)
                        }
                    }
                }
            }
            .padding(24)
        }
        .sheet(item: Binding(get: { editingPack.map(IdentifiedUUID.init) }, set: { editingPack = $0?.id })) { item in
            PackEditorSheet(packID: item.id)
        }
        .confirmationDialog("Delete “\(pendingDelete?.name ?? "")”?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Delete pack", role: .destructive) {
                if let pack = pendingDelete { model.deletePack(pack.id) }
                pendingDelete = nil
            }
        } message: {
            Text("Your imported sounds stay in My Sounds.")
        }
    }

    private func customRow(_ pack: CustomPack) -> some View {
        let isActive = model.config.activePack == .custom(pack.id)
        return HStack(spacing: 12) {
            SymbolTile(symbol: "theatermasks.fill", isActive: isActive)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(pack.name).font(.body.weight(.medium))
                    if isActive { Badge(text: "Active", color: Theme.accent) }
                }
                Text("Based on \(pack.base.title) · \(pack.overrides.count) custom trigger\(pack.overrides.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !isActive {
                Button("Use") { model.update { $0.selectingPack(.custom(pack.id)) } }
            }
            Button("Edit") { editingPack = pack.id }
            Menu {
                Button("Export…") { export(pack) }
                Divider()
                Button("Delete…", role: .destructive) { pendingDelete = pack }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .rowPadding()
    }

    private func export(_ pack: CustomPack) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(pack.name).\(PackArchive.fileExtension)"
        panel.canCreateDirectories = true
        panel.message = "Export a pack folder you can share with another Mac."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.exportPack(pack, to: url)
    }

    private func importPack() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a .soundpack folder."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.importPack(from: url)
    }
}

struct IdentifiedUUID: Identifiable {
    let id: UUID
}

private struct BuiltInPackCard: View {
    @Environment(AppModel.self) private var model
    let pack: BuiltInPack
    private static let previewMotifs: [Motif] = [.success, .rise, .click, .chime]
    @State private var previewStep = 0

    var body: some View {
        let isActive = model.config.activePack == .builtIn(pack)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SymbolTile(symbol: pack.symbol, isActive: true, size: 38)
                Spacer()
                if isActive { Badge(text: "Active", color: Theme.accent, symbol: "checkmark") }
            }
            Text(pack.title).font(.headline)
            Text(pack.tagline).font(.caption).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
            HStack {
                Button {
                    let motif = Self.previewMotifs[previewStep % Self.previewMotifs.count]
                    previewStep += 1
                    if let ref = pack.sounds(for: motif).first { model.preview(ref) }
                } label: {
                    Label("Listen", systemImage: "play.fill")
                }
                Spacer()
                Button(isActive ? "In use" : "Use pack") {
                    model.update { $0.selectingPack(.builtIn(pack)) }
                }
                .disabled(isActive)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            .strokeBorder(isActive ? Theme.accent : Color.primary.opacity(0.06), lineWidth: isActive ? 2 : 1))
    }
}
