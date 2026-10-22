import Foundation

extension TriggerID: CodingKeyRepresentable {}

public enum PlaybackMode: String, CaseIterable, Codable, Sendable {
    /// Cycle through the sounds in order, one per trigger.
    case rotate
    /// Pick any sound except the one played last time.
    case shuffle

    public var title: String {
        switch self {
        case .rotate: "Rotate in order"
        case .shuffle: "Shuffle"
        }
    }
}

/// Per-trigger choices the user makes.
public struct TriggerSetting: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    /// Empty means "follow the active pack".
    public var customSounds: [SoundRef]
    public var playback: PlaybackMode
    /// 0...1, multiplied with the master volume.
    public var volume: Double

    public static let `default` = TriggerSetting(isEnabled: false, customSounds: [], playback: .rotate, volume: 1)

    public init(isEnabled: Bool, customSounds: [SoundRef], playback: PlaybackMode, volume: Double) {
        self.isEnabled = isEnabled
        self.customSounds = customSounds
        self.playback = playback
        self.volume = volume.clamped(to: 0...1)
    }

    /// Unknown sound references are dropped instead of failing the whole config.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false,
            customSounds: container.decodeLossyArray(SoundRef.self, forKey: .customSounds) ?? [],
            playback: (try? container.decodeIfPresent(PlaybackMode.self, forKey: .playback)) ?? .rotate,
            volume: try container.decodeIfPresent(Double.self, forKey: .volume) ?? 1
        )
    }

    public var followsPack: Bool { customSounds.isEmpty }

    public func enabled(_ isEnabled: Bool) -> TriggerSetting {
        TriggerSetting(isEnabled: isEnabled, customSounds: customSounds, playback: playback, volume: volume)
    }

    public func withSounds(_ sounds: [SoundRef]) -> TriggerSetting {
        TriggerSetting(isEnabled: isEnabled, customSounds: sounds, playback: playback, volume: volume)
    }

    public func withPlayback(_ playback: PlaybackMode) -> TriggerSetting {
        TriggerSetting(isEnabled: isEnabled, customSounds: customSounds, playback: playback, volume: volume)
    }

    public func withVolume(_ volume: Double) -> TriggerSetting {
        TriggerSetting(isEnabled: isEnabled, customSounds: customSounds, playback: playback, volume: volume)
    }
}

/// A window of the day when nothing plays. Minutes are counted from midnight;
/// a window may wrap past midnight (e.g. 22:00 → 07:00).
public struct QuietHours: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    public var startMinute: Int
    public var endMinute: Int

    public static let `default` = QuietHours(isEnabled: false, startMinute: 22 * 60, endMinute: 7 * 60)

    public init(isEnabled: Bool, startMinute: Int, endMinute: Int) {
        self.isEnabled = isEnabled
        self.startMinute = startMinute.clamped(to: 0...(24 * 60 - 1))
        self.endMinute = endMinute.clamped(to: 0...(24 * 60 - 1))
    }

    public func contains(minuteOfDay minute: Int) -> Bool {
        guard isEnabled, startMinute != endMinute else { return false }
        if startMinute < endMinute {
            return minute >= startMinute && minute < endMinute
        }
        return minute >= startMinute || minute < endMinute
    }
}

/// A sound file the user imported into the app's library.
public struct UserSound: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let name: String
    /// File name inside the app's sounds folder (never a path).
    public let fileName: String
    public let duration: TimeInterval
    public let addedAt: Date

    public init(id: UUID = UUID(), name: String, fileName: String, duration: TimeInterval, addedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.duration = duration
        self.addedAt = addedAt
    }

    public func renamed(_ name: String) -> UserSound {
        UserSound(id: id, name: name, fileName: fileName, duration: duration, addedAt: addedAt)
    }
}

/// Everything the user configures. Value type: every change produces a new config.
public struct AppConfig: Codable, Sendable, Equatable {
    public static let currentVersion = 1
    public static let batteryLowRange = 2...99
    public static let batteryCriticalRange = 1...98
    public static let idleMinutesRange = 1...120

    public var version: Int
    public var isListening: Bool
    public var masterVolume: Double
    public var activePack: PackSelection
    public var customPacks: [CustomPack]
    public var triggers: [TriggerID: TriggerSetting]
    public var userSounds: [UserSound]
    public var quietHours: QuietHours
    public var batteryLowPercent: Int
    public var batteryCriticalPercent: Int
    public var idleMinutes: Int
    /// When several events land together (wake + display wake + unlock), only the first one sounds.
    public var avoidOverlap: Bool
    /// Keep the audio output running while you use the Mac so sounds start instantly.
    public var keepAudioReady: Bool
    /// Silence macOS's own sound for every enabled trigger that would otherwise play twice.
    public var replaceMacSounds: Bool
    /// Hide the floating screenshot thumbnail so captures (and their sound) are not delayed.
    public var hideScreenshotThumbnail: Bool
    /// macOS tweaks currently applied, with the values they replaced (one per `MacSoundTweak.keys` entry).
    public var appliedTweaks: [MacSoundTweak: [PrefValue]]

    public static var `default`: AppConfig {
        AppConfig(
            version: currentVersion, isListening: true, masterVolume: 0.7, activePack: .builtIn(.crystal),
            customPacks: [], triggers: [:], userSounds: [], quietHours: .default,
            batteryLowPercent: 20, batteryCriticalPercent: 10, idleMinutes: 5
        ).withRecommendedEnabled()
    }

    public init(version: Int, isListening: Bool, masterVolume: Double, activePack: PackSelection,
                customPacks: [CustomPack], triggers: [TriggerID: TriggerSetting], userSounds: [UserSound],
                quietHours: QuietHours, batteryLowPercent: Int, batteryCriticalPercent: Int, idleMinutes: Int,
                avoidOverlap: Bool = true, keepAudioReady: Bool = true, replaceMacSounds: Bool = true,
                hideScreenshotThumbnail: Bool = false, appliedTweaks: [MacSoundTweak: [PrefValue]] = [:]) {
        self.version = version
        self.isListening = isListening
        self.masterVolume = masterVolume.clamped(to: 0...1)
        self.activePack = activePack
        self.customPacks = customPacks
        self.triggers = triggers
        self.userSounds = userSounds
        self.quietHours = quietHours
        let low = batteryLowPercent.clamped(to: AppConfig.batteryLowRange)
        self.batteryLowPercent = low
        // Critical must stay below low, otherwise "low" would never be heard.
        self.batteryCriticalPercent = min(batteryCriticalPercent.clamped(to: AppConfig.batteryCriticalRange), low - 1)
        self.idleMinutes = idleMinutes.clamped(to: AppConfig.idleMinutesRange)
        self.avoidOverlap = avoidOverlap
        self.keepAudioReady = keepAudioReady
        self.replaceMacSounds = replaceMacSounds
        self.hideScreenshotThumbnail = hideScreenshotThumbnail
        self.appliedTweaks = appliedTweaks
    }

    /// Tolerant decoding: missing keys fall back to defaults so older or partial files still load.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppConfig.default
        self.init(
            version: try container.decodeIfPresent(Int.self, forKey: .version) ?? AppConfig.currentVersion,
            isListening: try container.decodeIfPresent(Bool.self, forKey: .isListening) ?? fallback.isListening,
            masterVolume: try container.decodeIfPresent(Double.self, forKey: .masterVolume) ?? fallback.masterVolume,
            activePack: (try? container.decodeIfPresent(PackSelection.self, forKey: .activePack)) ?? fallback.activePack,
            customPacks: container.decodeLossyArray(CustomPack.self, forKey: .customPacks) ?? [],
            triggers: container.decodeLossyTriggerMap(TriggerSetting.self, forKey: .triggers) ?? fallback.triggers,
            userSounds: container.decodeLossyArray(UserSound.self, forKey: .userSounds) ?? [],
            quietHours: try container.decodeIfPresent(QuietHours.self, forKey: .quietHours) ?? fallback.quietHours,
            batteryLowPercent: try container.decodeIfPresent(Int.self, forKey: .batteryLowPercent) ?? fallback.batteryLowPercent,
            batteryCriticalPercent: try container.decodeIfPresent(Int.self, forKey: .batteryCriticalPercent) ?? fallback.batteryCriticalPercent,
            idleMinutes: try container.decodeIfPresent(Int.self, forKey: .idleMinutes) ?? fallback.idleMinutes,
            avoidOverlap: (try? container.decodeIfPresent(Bool.self, forKey: .avoidOverlap)) ?? fallback.avoidOverlap,
            keepAudioReady: (try? container.decodeIfPresent(Bool.self, forKey: .keepAudioReady)) ?? fallback.keepAudioReady,
            replaceMacSounds: (try? container.decodeIfPresent(Bool.self, forKey: .replaceMacSounds)) ?? fallback.replaceMacSounds,
            hideScreenshotThumbnail: (try? container.decodeIfPresent(Bool.self, forKey: .hideScreenshotThumbnail)) ?? false,
            appliedTweaks: (try? container.decodeIfPresent([MacSoundTweak: [PrefValue]].self, forKey: .appliedTweaks)) ?? [:]
        )
    }

    public func setting(for trigger: TriggerID) -> TriggerSetting {
        triggers[trigger] ?? .default
    }

    public func isEnabled(_ trigger: TriggerID) -> Bool {
        setting(for: trigger).isEnabled
    }

    public var enabledTriggers: Set<TriggerID> {
        Set(triggers.filter { $0.value.isEnabled }.map(\.key))
    }

    public func customPack(id: UUID) -> CustomPack? {
        customPacks.first { $0.id == id }
    }

    public func userSound(id: UUID) -> UserSound? {
        userSounds.first { $0.id == id }
    }
}

// MARK: - Immutable updates

extension AppConfig {
    func copy(_ change: (inout AppConfig) -> Void) -> AppConfig {
        var next = self
        change(&next)
        return next
    }

    public func updatingTrigger(_ trigger: TriggerID, _ transform: (TriggerSetting) -> TriggerSetting) -> AppConfig {
        copy { $0.triggers[trigger] = transform(setting(for: trigger)) }
    }

    public func withRecommendedEnabled() -> AppConfig {
        TriggerCatalog.recommended.reduce(self) { config, trigger in
            config.updatingTrigger(trigger) { $0.enabled(true) }
        }
    }

    public func withAllTriggers(enabled: Bool, in category: TriggerCategory? = nil) -> AppConfig {
        TriggerCatalog.all
            .filter { category == nil || $0.category == category }
            .reduce(self) { config, info in config.updatingTrigger(info.id) { $0.enabled(enabled) } }
    }

    public func withListening(_ isListening: Bool) -> AppConfig {
        copy { $0.isListening = isListening }
    }

    public func withMasterVolume(_ volume: Double) -> AppConfig {
        copy { $0.masterVolume = volume.clamped(to: 0...1) }
    }

    public func withQuietHours(_ quietHours: QuietHours) -> AppConfig {
        copy { $0.quietHours = quietHours }
    }

    public func withBatteryThresholds(low: Int, critical: Int) -> AppConfig {
        let low = low.clamped(to: AppConfig.batteryLowRange)
        let critical = min(critical.clamped(to: AppConfig.batteryCriticalRange), low - 1)
        return copy {
            $0.batteryLowPercent = low
            $0.batteryCriticalPercent = critical
        }
    }

    /// Back to defaults, but the sound library is kept (no orphaned files) and so are applied
    /// macOS tweaks (their saved originals are the only way to restore the user's settings).
    public func reset() -> AppConfig {
        userSounds.reduce(AppConfig.default) { $0.addingUserSound($1) }
            .copy { $0.appliedTweaks = appliedTweaks }
    }

    public func withAvoidOverlap(_ isOn: Bool) -> AppConfig {
        copy { $0.avoidOverlap = isOn }
    }

    public func withKeepAudioReady(_ isOn: Bool) -> AppConfig {
        copy { $0.keepAudioReady = isOn }
    }

    public func withReplaceMacSounds(_ isOn: Bool) -> AppConfig {
        copy { $0.replaceMacSounds = isOn }
    }

    public func withHideScreenshotThumbnail(_ isOn: Bool) -> AppConfig {
        copy { $0.hideScreenshotThumbnail = isOn }
    }

    /// Which macOS tweaks should be in effect right now.
    /// Sound tweaks only apply while Sound Control is running, listening, and has an enabled
    /// trigger covering that moment — so macOS gets its sounds back whenever we are not replacing them.
    public func desiredTweaks(appIsRunning: Bool = true) -> Set<MacSoundTweak> {
        let enabled = enabledTriggers
        let sounds = MacSoundTweak.allCases.filter { tweak in
            tweak.isSound && appIsRunning && isListening && replaceMacSounds
                && !tweak.overlappingTriggers.isDisjoint(with: enabled)
        }
        return Set(sounds + (hideScreenshotThumbnail ? [.screenshotThumbnail] : []))
    }

    public func isApplied(_ tweak: MacSoundTweak) -> Bool {
        appliedTweaks[tweak] != nil
    }

    /// Records a tweak as applied. The first originals win, so re-applying never loses the user's values.
    public func applyingTweak(_ tweak: MacSoundTweak, originals: [PrefValue]) -> AppConfig {
        guard !isApplied(tweak) else { return self }
        return copy { $0.appliedTweaks[tweak] = originals }
    }

    public func revertingTweak(_ tweak: MacSoundTweak) -> AppConfig {
        copy { $0.appliedTweaks[tweak] = nil }
    }

    public func withIdleMinutes(_ minutes: Int) -> AppConfig {
        copy { $0.idleMinutes = minutes.clamped(to: AppConfig.idleMinutesRange) }
    }

    /// Selecting a custom pack that no longer exists falls back to Crystal.
    public func selectingPack(_ selection: PackSelection) -> AppConfig {
        if case let .custom(id) = selection, customPack(id: id) == nil {
            return copy { $0.activePack = .builtIn(.crystal) }
        }
        return copy { $0.activePack = selection }
    }

    public func addingCustomPack(_ pack: CustomPack) -> AppConfig {
        copy { $0.customPacks = $0.customPacks.filter { $0.id != pack.id } + [pack] }
    }

    public func updatingCustomPack(_ id: UUID, _ transform: (CustomPack) -> CustomPack) -> AppConfig {
        copy { $0.customPacks = $0.customPacks.map { $0.id == id ? transform($0) : $0 } }
    }

    public func removingCustomPack(_ id: UUID) -> AppConfig {
        let next = copy { $0.customPacks = $0.customPacks.filter { $0.id != id } }
        return next.activePack == .custom(id) ? next.selectingPack(.builtIn(.crystal)) : next
    }

    public func addingUserSound(_ sound: UserSound) -> AppConfig {
        copy { $0.userSounds = $0.userSounds.filter { $0.id != sound.id } + [sound] }
    }

    public func renamingUserSound(_ id: UUID, to name: String) -> AppConfig {
        copy { $0.userSounds = $0.userSounds.map { $0.id == id ? $0.renamed(name) : $0 } }
    }

    /// Removes the sound and every reference to it from triggers and custom packs.
    public func removingUserSound(_ id: UUID) -> AppConfig {
        let ref = SoundRef.user(id: id)
        return copy { config in
            config.userSounds = config.userSounds.filter { $0.id != id }
            config.triggers = config.triggers.mapValues { $0.withSounds($0.customSounds.filter { $0 != ref }) }
            config.customPacks = config.customPacks.map { pack in
                pack.overrides.keys.reduce(pack) { pack, trigger in
                    pack.overriding(trigger, with: (pack.overrides[trigger] ?? []).filter { $0 != ref })
                }
            }
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
