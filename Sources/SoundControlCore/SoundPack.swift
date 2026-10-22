import Foundation

/// Packs that ship with the app. Synth packs generate every motif from a timbre;
/// `system` maps motifs onto the sounds in /System/Library/Sounds.
public enum BuiltInPack: String, CaseIterable, Codable, Sendable {
    case crystal, arcade, marimba, cosmic, softKeys, system

    public var title: String {
        switch self {
        case .crystal: "Crystal"
        case .arcade: "Arcade"
        case .marimba: "Marimba"
        case .cosmic: "Cosmic"
        case .softKeys: "Soft Keys"
        case .system: "macOS Classic"
        }
    }

    public var tagline: String {
        switch self {
        case .crystal: "Bell-like glass tones that ring out"
        case .arcade: "Square-wave bleeps straight from an 8-bit cabinet"
        case .marimba: "Warm wooden mallets, short and friendly"
        case .cosmic: "Floating sine waves with a gentle wobble"
        case .softKeys: "Muted, close-up clicks made for typing"
        case .system: "The alert sounds already on your Mac"
        }
    }

    public var symbol: String {
        switch self {
        case .crystal: "sparkle"
        case .arcade: "gamecontroller.fill"
        case .marimba: "music.quarternote.3"
        case .cosmic: "moon.stars.fill"
        case .softKeys: "keyboard.fill"
        case .system: "apple.logo"
        }
    }

    /// nil for `system`, which plays files instead of synthesizing.
    public var timbre: Timbre? {
        switch self {
        case .crystal:
            Timbre(partials: [Partial(1, 1), Partial(2.76, 0.42), Partial(5.4, 0.18), Partial(8.93, 0.06)],
                   baseFrequency: 880, attack: 0.002, decay: 0.45, transient: 0.05, gain: 0.7)
        case .arcade:
            Timbre(partials: [Partial(1, 1)], waveform: .square, baseFrequency: 523.25,
                   attack: 0.001, decay: 0.12, gain: 0.45)
        case .marimba:
            Timbre(partials: [Partial(1, 1), Partial(3.93, 0.35), Partial(9.2, 0.08)],
                   baseFrequency: 392, attack: 0.002, decay: 0.16, transient: 0.12, gain: 0.85)
        case .cosmic:
            Timbre(partials: [Partial(1, 1), Partial(2, 0.25), Partial(3, 0.1)], waveform: .triangle,
                   baseFrequency: 329.63, attack: 0.03, decay: 0.6, vibratoDepth: 0.004, vibratoRate: 5.5, gain: 0.7)
        case .softKeys:
            Timbre(partials: [Partial(1, 1), Partial(1.5, 0.3)], baseFrequency: 220,
                   attack: 0.001, decay: 0.05, transient: 0.6, gain: 0.9)
        case .system:
            nil
        }
    }

    /// Takes the pack provides for a motif, used when a trigger "follows the pack".
    public func sounds(for motif: Motif) -> [SoundRef] {
        guard self == .system else {
            return (0..<Motif.takeCount).map { .synth(pack: self, motif: motif, take: $0) }
        }
        return BuiltInPack.systemSounds[motif, default: ["Tink"]].map { .system(name: $0) }
    }

    public static let systemSoundNames = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]

    private static let systemSounds: [Motif: [String]] = [
        .rise: ["Glass", "Ping"], .fall: ["Bottle"], .success: ["Hero"], .warning: ["Basso"],
        .alarm: ["Sosumi"], .ascend: ["Blow"], .descend: ["Submarine"], .chime: ["Ping"],
        .toll: ["Glass"], .tick: ["Tink"], .click: ["Tink"], .tap: ["Pop"], .pop: ["Pop"],
        .thud: ["Frog"], .doubleUp: ["Funk"], .doubleDown: ["Purr"], .sparkle: ["Glass", "Hero"],
        .whoosh: ["Morse"]
    ]
}

/// A pack the user authored ("you are the game master"): it starts from a built-in
/// pack and overrides whichever triggers the user wants.
public struct CustomPack: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let base: BuiltInPack
    public let overrides: [TriggerID: [SoundRef]]

    public init(id: UUID = UUID(), name: String, base: BuiltInPack, overrides: [TriggerID: [SoundRef]] = [:]) {
        self.id = id
        self.name = name
        self.base = base
        self.overrides = overrides
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, base, overrides
    }

    /// Overrides for unknown triggers or with unknown sounds are dropped, not fatal.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let overrides = container.decodeLossyTriggerMap([Lossy<SoundRef>].self, forKey: .overrides) ?? [:]
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            base: (try? container.decode(BuiltInPack.self, forKey: .base)) ?? .crystal,
            overrides: overrides.compactMapValues { refs in
                let valid = refs.compactMap(\.value)
                return valid.isEmpty ? nil : valid
            }
        )
    }

    public func renamed(_ name: String) -> CustomPack {
        CustomPack(id: id, name: name, base: base, overrides: overrides)
    }

    public func rebased(on base: BuiltInPack) -> CustomPack {
        CustomPack(id: id, name: name, base: base, overrides: overrides)
    }

    /// Empty `sounds` removes the override so the trigger falls back to the base pack.
    public func overriding(_ trigger: TriggerID, with sounds: [SoundRef]) -> CustomPack {
        var next = overrides
        next[trigger] = sounds.isEmpty ? nil : sounds
        return CustomPack(id: id, name: name, base: base, overrides: next)
    }
}

/// Which pack is currently driving triggers that follow the pack.
public enum PackSelection: Hashable, Sendable {
    case builtIn(BuiltInPack)
    case custom(UUID)
}

extension PackSelection: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let pack = BuiltInPack(rawValue: raw) {
            self = .builtIn(pack)
        } else if raw.hasPrefix("custom:"), let id = UUID(uuidString: String(raw.dropFirst("custom:".count))) {
            self = .custom(id)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown pack '\(raw)'")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .builtIn(pack): try container.encode(pack.rawValue)
        case let .custom(id): try container.encode("custom:\(id.uuidString)")
        }
    }
}
