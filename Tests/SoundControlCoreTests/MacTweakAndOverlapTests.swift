import Foundation
import Testing
@testable import SoundControlCore

@Suite("MacSoundTweak")
struct MacSoundTweakTests {
    @Test("every tweak is described and writes at least one key", arguments: MacSoundTweak.allCases)
    func described(tweak: MacSoundTweak) {
        #expect(!tweak.title.isEmpty && !tweak.detail.isEmpty)
        #expect(!tweak.keys.isEmpty)
        #expect(tweak.keys.allSatisfy { $0.silentValue != .absent && !$0.domain.isEmpty && !$0.key.isEmpty })
        #expect(!tweak.overlappingTriggers.isEmpty)
    }

    @Test("finds the macOS sound that doubles a trigger")
    func overlapLookup() {
        #expect(MacSoundTweak.soundTweak(overlapping: .chargerConnected) == .chargingChime)
        #expect(MacSoundTweak.soundTweak(overlapping: .screenshotTaken) == .interfaceSounds)
        #expect(MacSoundTweak.soundTweak(overlapping: .volumeChanged) == .volumeFeedback)
        #expect(MacSoundTweak.soundTweak(overlapping: .macWakes) == nil)
        #expect(!MacSoundTweak.screenshotThumbnail.isSound)
        #expect(MacSoundTweak.chargingChime.processesToRestart == ["PowerChime"])
    }

    @Test("applying keeps the first originals; reverting forgets them; reset keeps them")
    func applyRevert() throws {
        let applied = AppConfig.default.applyingTweak(.volumeFeedback, originals: [.absent])
        #expect(applied.isApplied(.volumeFeedback))
        let again = applied.applyingTweak(.volumeFeedback, originals: [.int(0)])
        #expect(again.appliedTweaks[.volumeFeedback] == [.absent])
        #expect(again.reset().appliedTweaks[.volumeFeedback] == [.absent])
        #expect(!again.revertingTweak(.volumeFeedback).isApplied(.volumeFeedback))

        let data = try JSONEncoder.soundControl.encode(applied.applyingTweak(.chargingChime, originals: [.bool(false)]))
        let decoded = try JSONDecoder.soundControl.decode(AppConfig.self, from: data)
        #expect(decoded.appliedTweaks == [.volumeFeedback: [.absent], .chargingChime: [.bool(false)]])
    }

    @Test("new switches default on and toggle immutably")
    func switches() {
        let config = AppConfig.default
        #expect(config.avoidOverlap && config.keepAudioReady)
        #expect(!config.withAvoidOverlap(false).avoidOverlap)
        #expect(!config.withKeepAudioReady(false).keepAudioReady)
        #expect(config.avoidOverlap)
    }
}

@Suite("Burst suppression")
struct BurstTests {
    let now = Date(timeIntervalSince1970: 12 * 3600)
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    @Test("a second event inside the burst window is skipped")
    func skipsBurst() {
        let decision = PlaybackGate.decide(.macWakes, config: .default, now: now, lastPlayed: nil,
                                           lastEventSound: now.addingTimeInterval(-0.1), calendar: calendar)
        #expect(decision == .skipped(.overlap))
        #expect(SkipReason.overlap.isWorthLogging)
    }

    @Test("outside the window, with the switch off, or for chatty triggers it plays")
    func allows() {
        let earlier = now.addingTimeInterval(-0.1)
        #expect(PlaybackGate.decide(.macWakes, config: .default, now: now, lastPlayed: nil,
                                    lastEventSound: now.addingTimeInterval(-1), calendar: calendar) == .play)
        #expect(PlaybackGate.decide(.macWakes, config: AppConfig.default.withAvoidOverlap(false), now: now,
                                    lastPlayed: nil, lastEventSound: earlier, calendar: calendar) == .play)
        let typing = AppConfig.default.updatingTrigger(.keyTyped) { $0.enabled(true) }
        #expect(PlaybackGate.decide(.keyTyped, config: typing, now: now, lastPlayed: nil,
                                    lastEventSound: earlier, calendar: calendar) == .play)
    }
}

@Suite("Desired macOS tweaks")
struct DesiredTweakTests {
    let base = AppConfig.default.withAllTriggers(enabled: false)

    @Test("a sound tweak follows its enabled trigger")
    func followsTrigger() {
        let charging = base.updatingTrigger(.chargerConnected) { $0.enabled(true) }
        #expect(charging.desiredTweaks() == [.chargingChime])
        #expect(base.desiredTweaks().isEmpty)
        let shots = base.updatingTrigger(.screenshotTaken) { $0.enabled(true) }
        #expect(shots.desiredTweaks() == [.interfaceSounds])
    }

    @Test("macOS gets its sounds back when not listening, opted out, or quitting")
    func restores() {
        let charging = base.updatingTrigger(.chargerConnected) { $0.enabled(true) }
        #expect(charging.withListening(false).desiredTweaks().isEmpty)
        #expect(charging.withReplaceMacSounds(false).desiredTweaks().isEmpty)
        #expect(charging.desiredTweaks(appIsRunning: false).isEmpty)
    }

    @Test("the thumbnail tweak is a standing user choice")
    func thumbnail() {
        let hidden = base.withHideScreenshotThumbnail(true)
        #expect(hidden.desiredTweaks() == [.screenshotThumbnail])
        #expect(hidden.withListening(false).desiredTweaks(appIsRunning: false) == [.screenshotThumbnail])
        #expect(AppConfig.default.replaceMacSounds && !AppConfig.default.hideScreenshotThumbnail)
    }

    @Test("defaults replace the chime and interface sounds for recommended triggers")
    func defaults() {
        #expect(AppConfig.default.desiredTweaks() == [.chargingChime, .interfaceSounds])
    }
}
