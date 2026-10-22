import Foundation

/// Decides which sounds a trigger may play and which one plays next.
public enum SoundResolver {
    /// Candidate sounds for a trigger, most specific source first:
    /// the trigger's own custom sounds → the active custom pack's override → the pack's base sounds.
    /// User sounds that were deleted are dropped.
    public static func candidates(for trigger: TriggerID, in config: AppConfig) -> [SoundRef] {
        let setting = config.setting(for: trigger)
        let motif = TriggerCatalog.info(for: trigger).motif
        let ordered: [SoundRef] = {
            if !setting.customSounds.isEmpty { return setting.customSounds }
            switch config.activePack {
            case let .builtIn(pack):
                return pack.sounds(for: motif)
            case let .custom(id):
                guard let pack = config.customPack(id: id) else { return BuiltInPack.crystal.sounds(for: motif) }
                return pack.overrides[trigger] ?? pack.base.sounds(for: motif)
            }
        }()
        return ordered.filter { isAvailable($0, in: config) }
    }

    /// Human readable source, e.g. "Crystal · 2 takes" or "Custom · 3 sounds".
    public static func sourceDescription(for trigger: TriggerID, in config: AppConfig) -> String {
        let setting = config.setting(for: trigger)
        let count = candidates(for: trigger, in: config).count
        let source = setting.followsPack ? packName(config.activePack, in: config) : "Custom"
        let noun = setting.followsPack ? "take" : "sound"
        return count == 1 ? source : "\(source) · \(count) \(noun)s"
    }

    public static func packName(_ selection: PackSelection, in config: AppConfig) -> String {
        switch selection {
        case let .builtIn(pack): pack.title
        case let .custom(id): config.customPack(id: id)?.name ?? "Missing pack"
        }
    }

    public static func displayName(of ref: SoundRef, in config: AppConfig) -> String {
        switch ref {
        case let .synth(pack, motif, take):
            take == 0 ? "\(pack.title) \(motif.title)" : "\(pack.title) \(motif.title) (take \(take + 1))"
        case let .system(name):
            name
        case let .user(id):
            config.userSound(id: id)?.name ?? "Missing sound"
        }
    }

    /// Index of the sound to play next.
    /// - Parameters:
    ///   - last: index played previously for this trigger, if any.
    ///   - random: injected so shuffle is testable; must return a value in `0..<upperBound`.
    public static func nextIndex(count: Int, last: Int?, mode: PlaybackMode,
                                 random: (Int) -> Int = { Int.random(in: 0..<$0) }) -> Int? {
        guard count > 0 else { return nil }
        guard count > 1 else { return 0 }
        switch mode {
        case .rotate:
            guard let last else { return 0 }
            return (last + 1) % count
        case .shuffle:
            guard let last, last < count else { return random(count) }
            // Draw from the other count-1 slots so the same sound never repeats back to back.
            let pick = random(count - 1)
            return pick >= last ? pick + 1 : pick
        }
    }

    static func isAvailable(_ ref: SoundRef, in config: AppConfig) -> Bool {
        if case let .user(id) = ref { return config.userSound(id: id) != nil }
        return true
    }
}
