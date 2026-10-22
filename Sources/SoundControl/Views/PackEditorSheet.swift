import SwiftUI
import SoundControlCore

/// Edit a custom pack: name, base pack, and a sound override for any trigger.
struct PackEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let packID: UUID
    @State private var search = ""

    var body: some View {
        if let pack = model.config.customPack(id: packID) {
            editor(pack)
        } else {
            VStack {
                Text("This pack no longer exists.")
                Button("Close") { dismiss() }
            }
            .padding(40)
        }
    }

    private func editor(_ pack: CustomPack) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                SymbolTile(symbol: "theatermasks.fill", size: 44)
                TextField("Pack name", text: Binding(
                    get: { pack.name },
                    set: { name in model.updatePack(packID) { $0.renamed(String(name.prefix(40))) } }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                Picker("Base", selection: Binding(
                    get: { pack.base },
                    set: { base in model.updatePack(packID) { $0.rebased(on: base) } }
                )) {
                    ForEach(BuiltInPack.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .frame(width: 200)
            }
            Text("Triggers without an override use the base pack. Pick a sound to override one.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("Search triggers", text: $search).textFieldStyle(.roundedBorder)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(TriggerCategory.allCases, id: \.self) { category in
                        let rows = TriggerCatalog.triggers(in: category).filter(matches)
                        if !rows.isEmpty {
                            Text(category.title.uppercased()).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                            Card {
                                ForEach(Array(rows.enumerated()), id: \.element.id) { index, info in
                                    if index > 0 { Divider().padding(.leading, 56) }
                                    overrideRow(info, pack: pack)
                                }
                            }
                        }
                    }
                }
            }

            HStack {
                if model.config.activePack != .custom(packID) {
                    Button("Use this pack") { model.update { $0.selectingPack(.custom(packID)) } }
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 640, height: 620)
    }

    private func overrideRow(_ info: TriggerInfo, pack: CustomPack) -> some View {
        let override = pack.overrides[info.id] ?? []
        let sounds = override.isEmpty ? pack.base.sounds(for: info.motif) : override
        return HStack(spacing: 10) {
            SymbolTile(symbol: info.symbol, isActive: !override.isEmpty, size: 28)
            Text(info.title)
            Spacer()
            Menu {
                Button("Use base pack") { model.updatePack(packID) { $0.overriding(info.id, with: []) } }
                Divider()
                SoundCatalogItems(selected: Set(override)) { ref in
                    model.updatePack(packID) { $0.overriding(info.id, with: [ref]) }
                    model.preview(ref)
                }
            } label: {
                Text(override.isEmpty ? "\(pack.base.title) · \(info.motif.title)"
                                      : SoundResolver.displayName(of: override[0], in: model.config))
                    .font(.caption.weight(.medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .foregroundStyle(override.isEmpty ? Color.secondary : Theme.accent)
            PlayButton {
                if let first = sounds.first { model.preview(first) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func matches(_ info: TriggerInfo) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return query.isEmpty || info.title.lowercased().contains(query)
    }
}
