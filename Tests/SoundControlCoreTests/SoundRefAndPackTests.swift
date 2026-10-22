import Foundation
import Testing
@testable import SoundControlCore

@Suite("SoundRef")
struct SoundRefTests {
    static let samples: [SoundRef] = [
        .synth(pack: .cosmic, motif: .sparkle, take: 1),
        .system(name: "Glass"),
        .user(id: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!)
    ]

    @Test("string form round-trips", arguments: samples)
    func roundTrip(ref: SoundRef) {
        #expect(SoundRef(string: ref.string) == ref)
    }

    @Test("codable round-trips through JSON", arguments: samples)
    func codable(ref: SoundRef) throws {
        let data = try JSONEncoder().encode([ref])
        #expect(try JSONDecoder().decode([SoundRef].self, from: data) == [ref])
    }

    @Test("rejects malformed and unsafe strings", arguments: [
        "", "synth", "synth:crystal:rise", "synth:nope:rise:0", "synth:crystal:nope:0",
        "synth:crystal:rise:9", "system:", "system:../../etc/passwd", "system:a/b",
        "user:not-a-uuid", "other:thing"
    ])
    func rejectsBadInput(raw: String) {
        #expect(SoundRef(string: raw) == nil)
    }

    @Test("decoding an unknown reference throws")
    func decodeThrows() {
        let data = Data(#"["bogus:1"]"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([SoundRef].self, from: data)
        }
    }
}

@Suite("Sound packs")
struct SoundPackTests {
    @Test("synth packs provide one ref per take", arguments: BuiltInPack.allCases.filter { $0 != .system })
    func synthTakes(pack: BuiltInPack) {
        let sounds = pack.sounds(for: .rise)
        #expect(sounds.count == Motif.takeCount)
        #expect(sounds.first == .synth(pack: pack, motif: .rise, take: 0))
        #expect(!pack.title.isEmpty && !pack.tagline.isEmpty && !pack.symbol.isEmpty)
    }

    @Test("system pack maps every motif to known system sounds")
    func systemMapping() {
        for motif in Motif.allCases {
            let sounds = BuiltInPack.system.sounds(for: motif)
            #expect(!sounds.isEmpty)
            for case let .system(name) in sounds {
                #expect(BuiltInPack.systemSoundNames.contains(name))
            }
        }
        #expect(BuiltInPack.system.timbre == nil)
    }

    @Test("custom pack overrides are added and cleared immutably")
    func customOverrides() {
        let pack = CustomPack(name: "Mine", base: .arcade)
        let edited = pack.overriding(.muted, with: [.system(name: "Pop")])
        #expect(pack.overrides.isEmpty)
        #expect(edited.overrides[.muted] == [.system(name: "Pop")])
        #expect(edited.overriding(.muted, with: []).overrides[.muted] == nil)
        #expect(edited.renamed("Other").name == "Other")
        #expect(edited.rebased(on: .cosmic).base == .cosmic)
        #expect(edited.renamed("Other").id == pack.id)
    }

    @Test("pack selection encodes both kinds")
    func selectionCodable() throws {
        let id = UUID()
        let values: [PackSelection] = [.builtIn(.marimba), .custom(id)]
        let data = try JSONEncoder().encode(values)
        #expect(try JSONDecoder().decode([PackSelection].self, from: data) == values)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([PackSelection].self, from: Data(#"["custom:zzz"]"#.utf8))
        }
    }
}
