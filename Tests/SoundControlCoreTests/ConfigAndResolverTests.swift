import Foundation
import Testing
@testable import SoundControlCore

@Suite("AppConfig")
struct AppConfigTests {
    @Test("defaults enable exactly the recommended triggers")
    func defaults() {
        let config = AppConfig.default
        #expect(config.enabledTriggers == TriggerCatalog.recommended)
        #expect(config.isListening)
        #expect(config.activePack == .builtIn(.crystal))
    }

    @Test("updates return a new value and leave the original untouched")
    func immutableUpdates() {
        let original = AppConfig.default
        let changed = original.updatingTrigger(.muted) { $0.enabled(true).withVolume(0.4) }
        #expect(!original.isEnabled(.muted))
        #expect(changed.isEnabled(.muted))
        #expect(changed.setting(for: .muted).volume == 0.4)
        #expect(original.withListening(false).isListening == false)
        #expect(original.isListening)
    }

    @Test("values are clamped into range")
    func clamping() {
        let config = AppConfig.default.withMasterVolume(3).withIdleMinutes(0)
        #expect(config.masterVolume == 1)
        #expect(config.idleMinutes == 1)
        #expect(TriggerSetting.default.withVolume(-2).volume == 0)
        let quiet = QuietHours(isEnabled: true, startMinute: -5, endMinute: 99_999)
        #expect(quiet.startMinute == 0 && quiet.endMinute == 24 * 60 - 1)
    }

    @Test("critical battery threshold always stays below low")
    func batteryThresholds() {
        let config = AppConfig.default.withBatteryThresholds(low: 15, critical: 40)
        #expect(config.batteryLowPercent == 15)
        #expect(config.batteryCriticalPercent == 14)
        let lowest = AppConfig.default.withBatteryThresholds(low: 1, critical: 1)
        #expect(lowest.batteryLowPercent == 2 && lowest.batteryCriticalPercent == 1)
        let clamped = AppConfig(version: 1, isListening: true, masterVolume: 1, activePack: .builtIn(.crystal),
                           customPacks: [], triggers: [:], userSounds: [], quietHours: .default,
                           batteryLowPercent: 10, batteryCriticalPercent: 50, idleMinutes: 5)
        #expect(clamped.batteryCriticalPercent == 9)
    }

    @Test("reset keeps the imported sound library")
    func resetKeepsSounds() {
        let sound = UserSound(name: "Quack", fileName: "x.wav", duration: 1)
        let reset = AppConfig.default.addingUserSound(sound).withMasterVolume(0.1).reset()
        #expect(reset.userSounds == [sound])
        #expect(reset.masterVolume == AppConfig.default.masterVolume)
    }

    @Test("unknown triggers, sounds and packs are dropped instead of failing")
    func lossyDecoding() throws {
        let packID = UUID()
        let json = """
        {
          "activePack": "from-the-future",
          "triggers": {
            "chargerConnected": {"isEnabled": true, "customSounds": ["system:Pop", "alien:thing"], "playback": "zigzag", "volume": 0.5},
            "teleported": {"isEnabled": true, "customSounds": [], "playback": "rotate", "volume": 1}
          },
          "customPacks": [
            {"id": "\(packID.uuidString)", "name": "GM", "base": "crystal",
             "overrides": {"muted": ["system:Frog", "bogus"], "flying": ["system:Pop"], "unmuted": ["bogus"]}},
            {"name": "missing id"}
          ],
          "userSounds": [{"nope": true}]
        }
        """
        let config = try JSONDecoder.soundControl.decode(AppConfig.self, from: Data(json.utf8))
        #expect(config.activePack == .builtIn(.crystal))
        #expect(config.setting(for: .chargerConnected).customSounds == [.system(name: "Pop")])
        #expect(config.setting(for: .chargerConnected).playback == .rotate)
        #expect(config.triggers.count == 1)
        #expect(config.customPacks.count == 1)
        #expect(config.customPack(id: packID)?.overrides == [.muted: [.system(name: "Frog")]])
        #expect(config.userSounds.isEmpty)
    }

    @Test("bulk enable and disable by category")
    func bulk() {
        let allOn = AppConfig.default.withAllTriggers(enabled: true)
        #expect(allOn.enabledTriggers == Set(TriggerID.allCases))
        let powerOff = allOn.withAllTriggers(enabled: false, in: .power)
        #expect(TriggerCatalog.triggers(in: .power).allSatisfy { !powerOff.isEnabled($0.id) })
        #expect(powerOff.isEnabled(.macWakes))
    }

    @Test("quiet hours handle same-day and overnight windows", arguments: [
        (600, 720, 650, true), (600, 720, 720, false), (600, 720, 599, false),
        (1320, 420, 1400, true), (1320, 420, 100, true), (1320, 420, 500, false), (600, 600, 600, false)
    ])
    func quietHours(start: Int, end: Int, minute: Int, expected: Bool) {
        #expect(QuietHours(isEnabled: true, startMinute: start, endMinute: end).contains(minuteOfDay: minute) == expected)
        #expect(!QuietHours(isEnabled: false, startMinute: start, endMinute: end).contains(minuteOfDay: minute))
    }

    @Test("removing a custom pack that is active falls back to Crystal")
    func removeActivePack() {
        let pack = CustomPack(name: "GM", base: .arcade)
        let config = AppConfig.default.addingCustomPack(pack).selectingPack(.custom(pack.id))
        #expect(config.activePack == .custom(pack.id))
        let removed = config.removingCustomPack(pack.id)
        #expect(removed.customPacks.isEmpty)
        #expect(removed.activePack == .builtIn(.crystal))
        #expect(AppConfig.default.selectingPack(.custom(UUID())).activePack == .builtIn(.crystal))
    }

    @Test("custom packs can be updated in place by id")
    func updatePack() {
        let pack = CustomPack(name: "GM", base: .arcade)
        let config = AppConfig.default.addingCustomPack(pack).updatingCustomPack(pack.id) { $0.renamed("Boss") }
        #expect(config.customPack(id: pack.id)?.name == "Boss")
        #expect(config.addingCustomPack(pack).customPacks.count == 1)
    }

    @Test("deleting a user sound removes every reference to it")
    func removeUserSound() {
        let sound = UserSound(name: "Quack", fileName: "\(UUID().uuidString).wav", duration: 1)
        let ref = SoundRef.user(id: sound.id)
        let pack = CustomPack(name: "GM", base: .crystal).overriding(.muted, with: [ref, .system(name: "Pop")])
            .overriding(.unmuted, with: [ref])
        let config = AppConfig.default
            .addingUserSound(sound)
            .addingCustomPack(pack)
            .updatingTrigger(.macWakes) { $0.withSounds([ref]) }
            .renamingUserSound(sound.id, to: "Duck")
        #expect(config.userSound(id: sound.id)?.name == "Duck")

        let cleaned = config.removingUserSound(sound.id)
        #expect(cleaned.userSounds.isEmpty)
        #expect(cleaned.setting(for: .macWakes).customSounds.isEmpty)
        #expect(cleaned.customPack(id: pack.id)?.overrides[.muted] == [.system(name: "Pop")])
        #expect(cleaned.customPack(id: pack.id)?.overrides[.unmuted] == nil)
    }

    @Test("JSON round-trip preserves the whole config")
    func jsonRoundTrip() throws {
        let pack = CustomPack(name: "GM", base: .cosmic).overriding(.keyTyped, with: [.system(name: "Tink")])
        let config = AppConfig.default
            .addingCustomPack(pack)
            .selectingPack(.custom(pack.id))
            .withQuietHours(QuietHours(isEnabled: true, startMinute: 60, endMinute: 120))
            .updatingTrigger(.spaceKey) { $0.enabled(true).withPlayback(.shuffle) }
        let data = try JSONEncoder.soundControl.encode(config)
        let decoded = try JSONDecoder.soundControl.decode(AppConfig.self, from: data)
        #expect(decoded == config)
        #expect(String(decoding: data, as: UTF8.self).contains("\"chargerConnected\""))
    }

    @Test("missing keys decode to defaults")
    func tolerantDecoding() throws {
        let decoded = try JSONDecoder.soundControl.decode(AppConfig.self, from: Data(#"{"masterVolume":0.2}"#.utf8))
        #expect(decoded.masterVolume == 0.2)
        #expect(decoded.enabledTriggers == TriggerCatalog.recommended)
        #expect(decoded.idleMinutes == AppConfig.default.idleMinutes)
    }
}

@Suite("SoundResolver")
struct SoundResolverTests {
    @Test("follows the active built-in pack by default")
    func followsPack() {
        let config = AppConfig.default.selectingPack(.builtIn(.arcade))
        #expect(SoundResolver.candidates(for: .chargerConnected, in: config) == BuiltInPack.arcade.sounds(for: .rise))
        #expect(SoundResolver.sourceDescription(for: .chargerConnected, in: config) == "Arcade · 2 takes")
    }

    @Test("custom trigger sounds beat the pack")
    func customWins() {
        let config = AppConfig.default.updatingTrigger(.chargerConnected) { $0.withSounds([.system(name: "Hero")]) }
        #expect(SoundResolver.candidates(for: .chargerConnected, in: config) == [.system(name: "Hero")])
        #expect(SoundResolver.sourceDescription(for: .chargerConnected, in: config) == "Custom")
    }

    @Test("custom pack override, then its base pack")
    func customPack() {
        let pack = CustomPack(name: "GM", base: .marimba).overriding(.muted, with: [.system(name: "Frog")])
        let config = AppConfig.default.addingCustomPack(pack).selectingPack(.custom(pack.id))
        #expect(SoundResolver.candidates(for: .muted, in: config) == [.system(name: "Frog")])
        #expect(SoundResolver.candidates(for: .unmuted, in: config) == BuiltInPack.marimba.sounds(for: .doubleUp))
        #expect(SoundResolver.packName(.custom(pack.id), in: config) == "GM")
    }

    @Test("a dangling custom pack selection falls back to Crystal sounds")
    func danglingPack() {
        var config = AppConfig.default
        config.activePack = .custom(UUID())
        #expect(SoundResolver.candidates(for: .macWakes, in: config) == BuiltInPack.crystal.sounds(for: .ascend))
        #expect(SoundResolver.packName(config.activePack, in: config) == "Missing pack")
    }

    @Test("deleted user sounds are not candidates")
    func dropsMissingUserSounds() {
        let config = AppConfig.default.updatingTrigger(.muted) { $0.withSounds([.user(id: UUID())]) }
        #expect(SoundResolver.candidates(for: .muted, in: config).isEmpty)
    }

    @Test("display names describe every kind of sound")
    func displayNames() {
        let sound = UserSound(name: "Quack", fileName: "x.wav", duration: 1)
        let config = AppConfig.default.addingUserSound(sound)
        #expect(SoundResolver.displayName(of: .synth(pack: .crystal, motif: .rise, take: 0), in: config) == "Crystal Rise")
        #expect(SoundResolver.displayName(of: .synth(pack: .crystal, motif: .rise, take: 1), in: config) == "Crystal Rise (take 2)")
        #expect(SoundResolver.displayName(of: .system(name: "Pop"), in: config) == "Pop")
        #expect(SoundResolver.displayName(of: .user(id: sound.id), in: config) == "Quack")
        #expect(SoundResolver.displayName(of: .user(id: UUID()), in: config) == "Missing sound")
    }

    @Test("rotate cycles in order")
    func rotate() {
        #expect(SoundResolver.nextIndex(count: 3, last: nil, mode: .rotate) == 0)
        #expect(SoundResolver.nextIndex(count: 3, last: 0, mode: .rotate) == 1)
        #expect(SoundResolver.nextIndex(count: 3, last: 2, mode: .rotate) == 0)
        #expect(SoundResolver.nextIndex(count: 0, last: nil, mode: .rotate) == nil)
        #expect(SoundResolver.nextIndex(count: 1, last: 0, mode: .shuffle) == 0)
    }

    @Test("shuffle never repeats the previous sound")
    func shuffle() {
        for pick in 0..<3 {
            let next = SoundResolver.nextIndex(count: 4, last: 1, mode: .shuffle, random: { _ in pick })
            #expect(next != 1)
        }
        #expect(SoundResolver.nextIndex(count: 4, last: nil, mode: .shuffle, random: { _ in 3 }) == 3)
        #expect(SoundResolver.nextIndex(count: 4, last: 9, mode: .shuffle, random: { _ in 2 }) == 2)
    }
}

@Suite("PlaybackGate")
struct PlaybackGateTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    let noon = Date(timeIntervalSince1970: 12 * 3600)

    @Test("plays an enabled trigger")
    func plays() {
        #expect(PlaybackGate.decide(.chargerConnected, config: .default, now: noon, lastPlayed: nil, calendar: calendar) == .play)
    }

    @Test("skip reasons in priority order")
    func skips() {
        let config = AppConfig.default
        #expect(PlaybackGate.decide(.chargerConnected, config: config.withListening(false), now: noon, lastPlayed: nil, calendar: calendar) == .skipped(.notListening))
        #expect(PlaybackGate.decide(.muted, config: config, now: noon, lastPlayed: nil, calendar: calendar) == .skipped(.triggerOff))
        let quiet = config.withQuietHours(QuietHours(isEnabled: true, startMinute: 11 * 60, endMinute: 13 * 60))
        #expect(PlaybackGate.decide(.chargerConnected, config: quiet, now: noon, lastPlayed: nil, calendar: calendar) == .skipped(.quietHours))
        #expect(PlaybackGate.decide(.chargerConnected, config: config, now: noon, lastPlayed: noon.addingTimeInterval(-0.1), calendar: calendar) == .skipped(.cooldown))
        let silent = config.updatingTrigger(.chargerConnected) { $0.withSounds([.user(id: UUID())]) }
        #expect(PlaybackGate.decide(.chargerConnected, config: silent, now: noon, lastPlayed: nil, calendar: calendar) == .skipped(.noSound))
    }

    @Test("cooldown expires")
    func cooldownExpires() {
        #expect(PlaybackGate.decide(.chargerConnected, config: .default, now: noon, lastPlayed: noon.addingTimeInterval(-2), calendar: calendar) == .play)
    }

    @Test("gain multiplies master and trigger volume")
    func gain() {
        let config = AppConfig.default.withMasterVolume(0.5).updatingTrigger(.muted) { $0.withVolume(0.5) }
        #expect(PlaybackGate.gain(for: .muted, config: config) == 0.25)
    }

    @Test("only meaningful skips are logged")
    func logging() {
        #expect(!SkipReason.triggerOff.isWorthLogging)
        #expect(!SkipReason.cooldown.isWorthLogging)
        #expect(SkipReason.quietHours.isWorthLogging)
    }

    @Test("playback modes have titles")
    func titles() {
        #expect(PlaybackMode.allCases.allSatisfy { !$0.title.isEmpty })
    }
}
