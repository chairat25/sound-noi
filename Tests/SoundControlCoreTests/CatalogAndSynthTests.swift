import Foundation
import Testing
@testable import SoundControlCore

@Suite("Trigger catalog")
struct TriggerCatalogTests {
    @Test("every trigger id is described exactly once")
    func everyTriggerRegistered() {
        let ids = TriggerCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(Set(ids) == Set(TriggerID.allCases))
    }

    @Test("every category has at least one trigger")
    func categoriesNotEmpty() {
        for category in TriggerCategory.allCases {
            #expect(!TriggerCatalog.triggers(in: category).isEmpty, "\(category) is empty")
            #expect(!category.title.isEmpty)
        }
    }

    @Test("input triggers require input monitoring and have no cooldown")
    func inputTriggersNeedPermission() {
        for info in TriggerCatalog.triggers(in: .input) {
            #expect(info.permission == .inputMonitoring)
        }
        #expect(TriggerCatalog.info(for: .keyTyped).cooldown == 0)
    }

    @Test("high-frequency triggers are marked chatty")
    func chatty() {
        #expect(TriggerCatalog.info(for: .keyTyped).isChatty)
        #expect(TriggerCatalog.info(for: .volumeChanged).isChatty)
        #expect(!TriggerCatalog.info(for: .chargerConnected).isChatty)
        #expect(!TriggerCatalog.info(for: .capsLockOn).isChatty)
    }

    @Test("recommended set never needs a permission prompt")
    func recommendedNeedsNoPermission() {
        for id in TriggerCatalog.recommended {
            #expect(TriggerCatalog.info(for: id).permission == .none, "\(id)")
        }
        #expect(TriggerCatalog.recommended.contains(.chargerConnected))
    }
}

@Suite("Motifs")
struct MotifTests {
    @Test("every motif has notes for every take", arguments: Motif.allCases)
    func notesExist(motif: Motif) {
        for take in 0..<Motif.takeCount {
            let notes = motif.notes(take: take)
            #expect(!notes.isEmpty)
            #expect(notes.allSatisfy { $0.duration > 0 && $0.start >= 0 })
            #expect(!motif.title.isEmpty)
        }
    }

    @Test("second take is transposed and faster")
    func takesDiffer() {
        let first = Motif.rise.notes(take: 0)
        let second = Motif.rise.notes(take: 1)
        #expect(second[0].semitone == first[0].semitone + 2)
        #expect(second[1].start < first[1].start)
    }

    @Test("out of range takes wrap instead of crashing")
    func takeWraps() {
        #expect(Motif.pop.notes(take: 2) == Motif.pop.notes(take: 0))
        #expect(Motif.pop.notes(take: -1) == Motif.pop.notes(take: 1))
    }
}

@Suite("Synth")
struct SynthTests {
    static let synthPacks = BuiltInPack.allCases.filter { $0.timbre != nil }

    @Test("renders audible, normalized audio for every pack", arguments: synthPacks)
    func rendersEveryPack(pack: BuiltInPack) throws {
        let timbre = try #require(pack.timbre)
        for motif in Motif.allCases {
            let samples = Synth.render(motif, take: 0, timbre: timbre, sampleRate: 8_000)
            let peak = samples.map(abs).max() ?? 0
            #expect(!samples.isEmpty)
            #expect(peak > 0.5, "\(pack) \(motif) is too quiet")
            #expect(peak <= 1, "\(pack) \(motif) clips")
            #expect(samples.allSatisfy { $0.isFinite })
        }
    }

    @Test("rendering is deterministic")
    func deterministic() throws {
        let timbre = try #require(BuiltInPack.softKeys.timbre)
        let a = Synth.render(.click, take: 1, timbre: timbre, sampleRate: 8_000)
        let b = Synth.render(.click, take: 1, timbre: timbre, sampleRate: 8_000)
        #expect(a == b)
    }

    @Test("length covers the last note plus the tail")
    func lengthCoversNotes() throws {
        let timbre = try #require(BuiltInPack.arcade.timbre)
        let rate = 8_000.0
        let samples = Synth.render(.success, take: 0, timbre: timbre, sampleRate: rate)
        let end = Motif.success.notes(take: 0).map { $0.start + $0.duration }.max()!
        #expect(samples.count == Int((end + Synth.tailSeconds) * rate))
    }

    @Test("frequency doubles every octave")
    func frequencyMath() {
        #expect(Synth.frequency(semitone: 12, base: 440) == 880)
        #expect(abs(Synth.frequency(semitone: 7, base: 440) - 659.255) < 0.01)
    }

    @Test("silence stays silent when normalized")
    func normalizeSilence() {
        #expect(Synth.normalized([0, 0, 0]) == [0, 0, 0])
        #expect(Synth.normalized([0.5, -0.25]).first == Synth.peakTarget)
    }

    @Test("oscillators stay within -1...1")
    func oscillatorRange() {
        for waveform in [Waveform.sine, .square, .triangle] {
            for step in 0..<64 {
                let value = Synth.oscillate(waveform, phase: Double(step) * 0.3)
                #expect((-1...1).contains(value))
            }
        }
    }

    @Test("envelope attacks, decays and releases to zero")
    func envelopeShape() {
        #expect(Synth.envelopeValue(t: 0, attack: 0.01, decay: 0.5, releaseStart: 1, end: 2) == 0)
        #expect(Synth.envelopeValue(t: 0.01, attack: 0.01, decay: 0.5, releaseStart: 1, end: 2) == 1)
        #expect(Synth.envelopeValue(t: 2, attack: 0.01, decay: 0.5, releaseStart: 1, end: 2) == 0)
    }

    @Test("noise generator stays in range and never sticks at zero seed")
    func noiseRange() {
        var noise = NoiseGenerator(seed: 0)
        let values = (0..<500).map { _ in noise.next() }
        #expect(values.allSatisfy { (-1...1).contains($0) })
        #expect(Set(values).count > 400)
    }
}
