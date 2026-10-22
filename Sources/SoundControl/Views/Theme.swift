import SwiftUI
import SoundControlCore

enum Theme {
    static let accent = Color(red: 0.56, green: 0.43, blue: 1.0)
    static let accentSoft = accent.opacity(0.16)
    static let warning = Color.orange
    static let cardRadius: CGFloat = 12
    static let tileSize: CGFloat = 32
}

/// Rounded square holding a trigger or pack symbol.
struct SymbolTile: View {
    let symbol: String
    var isActive = true
    var size: CGFloat = Theme.tileSize

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(isActive ? Theme.accent : .secondary)
            .frame(width: size, height: size)
            .background(isActive ? Theme.accentSoft : Color.secondary.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// Grouped card container used by every page.
struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06)))
    }
}

/// Small capsule label ("2 takes", "Needs permission").
struct Badge: View {
    let text: String
    var color: Color = .secondary
    var symbol: String?

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.14), in: Capsule())
    }
}

struct PageHeader<Accessory: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.largeTitle.weight(.bold))
                Text(subtitle).foregroundStyle(.secondary)
            }
            Spacer()
            accessory
        }
    }
}

/// Round play button used next to sounds and triggers.
struct PlayButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "play.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 24, height: 24)
                .background(Theme.accentSoft, in: Circle())
        }
        .buttonStyle(.plain)
        .help("Preview")
    }
}

extension View {
    func rowPadding() -> some View {
        padding(.horizontal, 14).padding(.vertical, 10)
    }
}
