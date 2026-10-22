import Foundation
import OSLog
import SoundControlCore

/// Reads and writes other apps' preferences (what `defaults` does), used to silence
/// macOS sounds that would play on top of ours.
enum MacPreferences {
    private static let logger = Logger(subsystem: "com.pond.soundcontrol", category: "MacPreferences")

    static func read(_ key: PrefKey) -> PrefValue {
        guard let value = CFPreferencesCopyValue(key.key as CFString, domain(key), kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            return .absent
        }
        if CFGetTypeID(value) == CFBooleanGetTypeID() {
            return .bool(CFBooleanGetValue((value as! CFBoolean)))
        }
        if let number = value as? NSNumber {
            return .int(number.intValue)
        }
        // An unexpected type: treat as absent so reverting deletes the key we wrote.
        return .absent
    }

    @discardableResult
    static func write(_ value: PrefValue, to key: PrefKey) -> Bool {
        let cfValue: CFPropertyList? = switch value {
        case .absent: nil
        case let .bool(flag): flag as CFBoolean
        case let .int(number): number as CFNumber
        }
        CFPreferencesSetValue(key.key as CFString, cfValue, domain(key), kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        let synced = CFPreferencesSynchronize(domain(key), kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        if !synced { logger.error("Could not write \(key.domain, privacy: .public) \(key.key, privacy: .public)") }
        return synced && read(key) == value
    }

    /// Applies a tweak and returns the values it replaced, or nil if macOS refused the write.
    static func apply(_ tweak: MacSoundTweak) -> [PrefValue]? {
        let originals = tweak.keys.map(read)
        let written = tweak.keys.map { write($0.silentValue, to: $0) }
        guard written.contains(true) else {
            zip(tweak.keys, originals).forEach { write($1, to: $0) }
            return nil
        }
        announce(tweak)
        return originals
    }

    static func revert(_ tweak: MacSoundTweak, originals: [PrefValue]) {
        zip(tweak.keys, originals).forEach { write($1, to: $0) }
        announce(tweak)
    }

    /// Lets running system processes notice the change.
    private static func announce(_ tweak: MacSoundTweak) {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.apple.sound.settingsChangedNotification"), object: nil, userInfo: nil,
            deliverImmediately: true)
        for process in tweak.processesToRestart {
            let killall = Process()
            killall.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            killall.arguments = [process]
            do {
                try killall.run()
            } catch {
                logger.error("killall \(process, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func domain(_ key: PrefKey) -> CFString {
        key.domain == PrefKey.globalDomain ? kCFPreferencesAnyApplication : key.domain as CFString
    }
}
