import SwiftUI
import SoundControlCore

struct ActivityPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Activity",
                           subtitle: "What your Mac did and what it sounded like. Keys, clicks and volume ticks are not logged.") {
                    Text("\(model.log.playCount(since: Calendar.current.startOfDay(for: Date()))) sounds today")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if model.log.entries.isEmpty {
                    ContentUnavailableView("Nothing yet", systemImage: "waveform.path",
                                           description: Text("Plug in your charger or lock the screen to see events here."))
                        .padding(.top, 40)
                } else {
                    Card {
                        ForEach(Array(model.log.entries.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 { Divider().padding(.leading, 60) }
                            ActivityRow(entry: entry)
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

struct ActivityRow: View {
    let entry: ActivityEntry
    var compact = false

    var body: some View {
        let info = TriggerCatalog.info(for: entry.trigger)
        HStack(spacing: 12) {
            SymbolTile(symbol: info.symbol, isActive: entry.didPlay, size: compact ? 24 : Theme.tileSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(info.title).font(compact ? .callout : .body.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(entry.date, style: .time).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, compact ? 0 : 14)
        .padding(.vertical, compact ? 3 : 9)
    }

    private var subtitle: String {
        let outcome = entry.skipReason.map { "Skipped: \($0.rawValue)" } ?? "♪ \(entry.soundName ?? "Sound")"
        guard let context = entry.context, !context.isEmpty else { return outcome }
        return "\(context) · \(outcome)"
    }
}
