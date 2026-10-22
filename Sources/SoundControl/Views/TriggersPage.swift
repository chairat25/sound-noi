import SwiftUI
import SoundControlCore

struct TriggersPage: View {
    enum Filter: String, CaseIterable {
        case all = "All", on = "On", off = "Off"
    }

    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var filter = Filter.all
    @State private var editing: TriggerID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Triggers",
                           subtitle: "Every moment on your Mac can make a sound. Pick one, or let your pack decide.") {
                    actions
                }
                toolbar
                ForEach(TriggerCategory.allCases, id: \.self) { category in
                    let rows = visibleTriggers(in: category)
                    if !rows.isEmpty {
                        section(category, rows: rows)
                    }
                }
                if TriggerCategory.allCases.allSatisfy({ visibleTriggers(in: $0).isEmpty }) {
                    ContentUnavailableView.search(text: search)
                }
            }
            .padding(24)
        }
        .sheet(item: $editing) { trigger in
            TriggerDetailSheet(trigger: trigger)
        }
    }

    private var actions: some View {
        HStack {
            Button {
                model.update { $0.withRecommendedEnabled() }
            } label: {
                Label("Turn on recommended", systemImage: "wand.and.stars")
            }
            Menu {
                Button("Turn everything on") { model.update { $0.withAllTriggers(enabled: true) } }
                Button("Turn everything off") { model.update { $0.withAllTriggers(enabled: false) } }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search triggers", text: $search).textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(7)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: 320)
            Picker("Filter", selection: $filter) {
                ForEach(Filter.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 170)
            Spacer()
            Text("\(model.config.enabledTriggers.count) of \(TriggerID.allCases.count) on")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func section(_ category: TriggerCategory, rows: [TriggerInfo]) -> some View {
        let all = TriggerCatalog.triggers(in: category)
        let onCount = all.filter { model.config.isEnabled($0.id) }.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(category.title.uppercased()).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                Text("· \(onCount) of \(all.count) on").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button(onCount == all.count ? "Turn all off" : "Turn all on") {
                    model.update { $0.withAllTriggers(enabled: onCount != all.count, in: category) }
                }
                .buttonStyle(.link)
                .font(.caption)
            }
            Card {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, info in
                    if index > 0 { Divider().padding(.leading, 60) }
                    TriggerRow(info: info) { editing = info.id }
                }
            }
        }
    }

    private func visibleTriggers(in category: TriggerCategory) -> [TriggerInfo] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return TriggerCatalog.triggers(in: category).filter { info in
            let matchesSearch = query.isEmpty || info.title.lowercased().contains(query)
                || info.detail.lowercased().contains(query) || category.title.lowercased().contains(query)
            let isOn = model.config.isEnabled(info.id)
            let matchesFilter = filter == .all || (filter == .on && isOn) || (filter == .off && !isOn)
            return matchesSearch && matchesFilter
        }
    }
}

extension TriggerID: Identifiable {
    public var id: String { rawValue }
}

struct TriggerRow: View {
    @Environment(AppModel.self) private var model
    let info: TriggerInfo
    let onEdit: () -> Void

    var body: some View {
        let isOn = model.config.isEnabled(info.id)
        HStack(spacing: 12) {
            SymbolTile(symbol: info.symbol, isActive: isOn)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(info.title).font(.body.weight(.medium))
                    if info.isRecommended { Badge(text: "Recommended", color: Theme.accent) }
                    if info.permission == .inputMonitoring { Badge(text: "Input Monitoring", symbol: "hand.raised.fill") }
                    if info.permission == .bluetooth { Badge(text: "Bluetooth", symbol: "hand.raised.fill") }
                }
                HStack(spacing: 6) {
                    Text(info.detail)
                    Text("·")
                    Text(SoundResolver.sourceDescription(for: info.id, in: model.config))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                if isOn, let tweak = MacSoundTweak.soundTweak(overlapping: info.id) {
                    if model.config.isApplied(tweak) {
                        Label("Replaces the macOS \(tweak.title.lowercased())", systemImage: "speaker.slash")
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "speaker.wave.2.bubble")
                            Text("macOS plays its own sound here too.")
                            Button("Replace it") { model.update { $0.withReplaceMacSounds(true) } }
                                .buttonStyle(.link)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                if let reason = model.unavailable[info.id], isOn {
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                }
            }
            Spacer(minLength: 8)
            TriggerSoundMenu(trigger: info.id)
            PlayButton { model.preview(info.id) }
            Button(action: onEdit) {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Sounds, volume and rotation")
            Toggle("", isOn: Binding(get: { isOn }, set: { model.setTrigger(info.id, enabled: $0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(Theme.accent)
        }
        .rowPadding()
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
    }
}
