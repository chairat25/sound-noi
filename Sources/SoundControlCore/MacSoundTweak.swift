import Foundation

/// A preference value as stored in a macOS plist. `absent` means the key was not set.
public enum PrefValue: Codable, Equatable, Sendable {
    case absent
    case bool(Bool)
    case int(Int)
}

/// One `defaults` key: which domain, which key, and the value that silences macOS.
public struct PrefKey: Equatable, Sendable {
    /// Use `PrefKey.globalDomain` for NSGlobalDomain (`defaults -g`).
    public let domain: String
    public let key: String
    public let silentValue: PrefValue

    public static let globalDomain = "NSGlobalDomain"
}

/// macOS sounds (and one UI delay) that overlap with Sound Control's own triggers.
/// Applying a tweak writes `silentValue`; reverting writes back what was there before.
public enum MacSoundTweak: String, CaseIterable, Codable, Sendable, CodingKeyRepresentable {
    case chargingChime
    case interfaceSounds
    case volumeFeedback
    case screenshotThumbnail

    public var title: String {
        switch self {
        case .chargingChime: "Charging chime"
        case .interfaceSounds: "Interface sound effects"
        case .volumeFeedback: "Volume change feedback"
        case .screenshotThumbnail: "Floating screenshot thumbnail"
        }
    }

    public var detail: String {
        switch self {
        case .chargingChime: "The chime a MacBook plays when the charger is plugged in."
        case .interfaceSounds: "Screenshot shutter, emptying the Trash, moving files and other Finder sounds."
        case .volumeFeedback: "The pop macOS plays while you change the volume."
        case .screenshotThumbnail: "Not a sound — while the preview sits in the corner, the file is saved ~5 s late, so the screenshot sound is late too."
        }
    }

    public var keys: [PrefKey] {
        switch self {
        case .chargingChime:
            [PrefKey(domain: "com.apple.PowerChime", key: "ChimeOnNoHardware", silentValue: .bool(true))]
        case .interfaceSounds:
            // Newer macOS reads the global key; older releases used the systemsound domain. Write both.
            [PrefKey(domain: PrefKey.globalDomain, key: "com.apple.sound.uiaudio.enabled", silentValue: .int(0)),
             PrefKey(domain: "com.apple.systemsound", key: "com.apple.sound.uiaudio.enabled", silentValue: .int(0))]
        case .volumeFeedback:
            [PrefKey(domain: PrefKey.globalDomain, key: "com.apple.sound.beep.feedback", silentValue: .int(0))]
        case .screenshotThumbnail:
            [PrefKey(domain: "com.apple.screencapture", key: "show-thumbnail", silentValue: .bool(false))]
        }
    }

    /// Background processes that only pick up the change after a restart (launchd relaunches them).
    public var processesToRestart: [String] {
        switch self {
        case .chargingChime: ["PowerChime"]
        case .interfaceSounds, .volumeFeedback: []
        case .screenshotThumbnail: ["SystemUIServer"]
        }
    }

    /// Triggers whose sound doubles up with this macOS behavior.
    public var overlappingTriggers: Set<TriggerID> {
        switch self {
        case .chargingChime: [.chargerConnected]
        case .interfaceSounds: [.screenshotTaken, .trashChanged]
        case .volumeFeedback: [.volumeChanged]
        case .screenshotThumbnail: [.screenshotTaken]
        }
    }

    public var isSound: Bool { self != .screenshotThumbnail }

    /// The tweak that would silence macOS's own sound for a trigger, if any.
    public static func soundTweak(overlapping trigger: TriggerID) -> MacSoundTweak? {
        allCases.first { $0.isSound && $0.overlappingTriggers.contains(trigger) }
    }
}
