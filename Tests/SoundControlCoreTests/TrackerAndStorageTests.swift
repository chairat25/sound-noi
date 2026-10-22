import Foundation
import Testing
@testable import SoundControlCore

@Suite("Edge")
struct EdgeTests {
    @Test("fires only on change, never on first sample")
    func edges() {
        #expect(Edge.detect(previous: nil, current: true, rising: .muted, falling: .unmuted) == nil)
        #expect(Edge.detect(previous: true, current: true, rising: .muted, falling: .unmuted) == nil)
        #expect(Edge.detect(previous: false, current: true, rising: .muted, falling: .unmuted) == .muted)
        #expect(Edge.detect(previous: true, current: false, rising: .muted, falling: .unmuted) == .unmuted)
    }
}

@Suite("BatteryTracker")
struct BatteryTrackerTests {
    func events(_ from: BatterySnapshot?, _ to: BatterySnapshot) -> [TriggerID] {
        BatteryTracker.events(from: from, to: to, lowPercent: 20, criticalPercent: 10)
    }

    @Test("first reading is silent")
    func firstReading() {
        #expect(events(nil, BatterySnapshot(isOnAC: true, percent: 100, isCharged: true)).isEmpty)
    }

    @Test("plug and unplug")
    func plug() {
        let battery = BatterySnapshot(isOnAC: false, percent: 50, isCharged: false)
        let charging = BatterySnapshot(isOnAC: true, percent: 50, isCharged: false)
        #expect(events(battery, charging) == [.chargerConnected])
        #expect(events(charging, battery) == [.chargerDisconnected])
    }

    @Test("reaching full charge fires once")
    func full() {
        let charging = BatterySnapshot(isOnAC: true, percent: 99, isCharged: false)
        let full = BatterySnapshot(isOnAC: true, percent: 100, isCharged: true)
        #expect(events(charging, full) == [.batteryFull])
        #expect(events(full, full).isEmpty)
    }

    @Test("low and critical thresholds")
    func thresholds() {
        let at21 = BatterySnapshot(isOnAC: false, percent: 21, isCharged: false)
        let at20 = BatterySnapshot(isOnAC: false, percent: 20, isCharged: false)
        let at11 = BatterySnapshot(isOnAC: false, percent: 11, isCharged: false)
        let at10 = BatterySnapshot(isOnAC: false, percent: 10, isCharged: false)
        #expect(events(at21, at20) == [.batteryLow])
        #expect(events(at20, at20).isEmpty)
        #expect(events(at11, at10) == [.batteryCritical])
        #expect(events(at21, at10) == [.batteryCritical])
        #expect(events(BatterySnapshot(isOnAC: true, percent: 21, isCharged: false),
                       BatterySnapshot(isOnAC: true, percent: 20, isCharged: false)).isEmpty)
    }
}

@Suite("IdleTracker")
struct IdleTrackerTests {
    @Test("goes idle after the threshold and returns on input")
    func cycle() {
        let start = IdleTracker()
        let (stillActive, none) = start.update(secondsSinceInput: 10, idleThreshold: 60)
        #expect(none == nil && !stillActive.isIdle)
        let (idle, went) = start.update(secondsSinceInput: 61, idleThreshold: 60)
        #expect(went == .idleStarted && idle.isIdle)
        let (stillIdle, quiet) = idle.update(secondsSinceInput: 120, idleThreshold: 60)
        #expect(quiet == nil && stillIdle.isIdle)
        let (back, returned) = idle.update(secondsSinceInput: 1, idleThreshold: 60)
        #expect(returned == .idleReturned && !back.isIdle)
    }
}

@Suite("ClockChime")
struct ClockChimeTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func at(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        Date(timeIntervalSince1970: TimeInterval(hour * 3600 + minute * 60 + second))
    }

    @Test("chimes on the hour and half hour")
    func chimes() {
        #expect(ClockChime.chime(from: at(9, 59, 50), to: at(10, 0, 5), calendar: calendar) == .hourlyChime)
        #expect(ClockChime.chime(from: at(10, 29, 50), to: at(10, 30, 0), calendar: calendar) == .halfHourChime)
        #expect(ClockChime.chime(from: at(10, 10), to: at(10, 10, 20), calendar: calendar) == nil)
    }

    @Test("never chimes for long gaps or backwards time")
    func gaps() {
        #expect(ClockChime.chime(from: at(9, 0), to: at(11, 0), calendar: calendar) == nil)
        #expect(ClockChime.chime(from: at(10, 1), to: at(9, 59), calendar: calendar) == nil)
        // A short sleep across the hour is still a gap, not a chime.
        #expect(ClockChime.chime(from: at(9, 58), to: at(10, 1), calendar: calendar) == nil)
    }
}

@Suite("Small rules")
struct SmallRuleTests {
    @Test("thermal states serious and above are hot")
    func thermal() {
        #expect(!ThermalLevel.isHot(rawState: 1))
        #expect(ThermalLevel.isHot(rawState: 2))
    }

    @Test("download filter ignores partial and hidden files", arguments: [
        ("report.pdf", true), ("movie.mp4.crdownload", false), ("x.download", false),
        (".DS_Store", false), ("", false), ("archive.PART", false), ("song.mp3", true)
    ])
    func downloads(name: String, expected: Bool) {
        #expect(DownloadFilter.isFinishedDownload(name) == expected)
    }

    @Test("new downloads are the finished files that appeared")
    func newDownloads() {
        let before: Set = ["a.pdf", "b.zip.crdownload"]
        let after: Set = ["a.pdf", "b.zip", "c.tmp", "d.png"]
        #expect(DownloadFilter.newDownloads(before: before, after: after) == ["b.zip", "d.png"])
    }

    @Test("activity log is newest first and bounded")
    func activityLog() {
        let start = Date()
        let log = (0..<(ActivityLog.capacity + 5)).reduce(ActivityLog()) { log, index in
            log.appending(ActivityEntry(trigger: .keyTyped, date: start.addingTimeInterval(Double(index)),
                                        skipReason: index.isMultiple(of: 2) ? nil : .quietHours,
                                        soundName: nil, context: nil))
        }
        #expect(log.entries.count == ActivityLog.capacity)
        #expect(log.entries.first?.date == start.addingTimeInterval(Double(ActivityLog.capacity + 4)))
        #expect(log.playCount(since: start.addingTimeInterval(Double(ActivityLog.capacity))) == 3)
    }
}

@Suite("Audio import rules")
struct AudioImportTests {
    @Test("accepts a normal sound")
    func accepts() throws {
        try AudioImport.check(fileExtension: "MP3", bytes: 1_000, duration: 2)
    }

    @Test("rejects bad files")
    func rejects() {
        #expect(throws: AudioImport.Rejection.unsupportedType("exe")) {
            try AudioImport.check(fileExtension: "exe", bytes: 10, duration: 1)
        }
        #expect(throws: AudioImport.Rejection.tooLarge(AudioImport.maximumBytes + 1)) {
            try AudioImport.check(fileExtension: "wav", bytes: AudioImport.maximumBytes + 1, duration: 1)
        }
        #expect(throws: AudioImport.Rejection.tooLong(31)) {
            try AudioImport.check(fileExtension: "wav", bytes: 10, duration: 31)
        }
        #expect(throws: AudioImport.Rejection.unreadable) {
            try AudioImport.check(fileExtension: "wav", bytes: 10, duration: nil)
        }
        let all: [AudioImport.Rejection] = [.unsupportedType("x"), .tooLarge(1), .tooLong(40), .unreadable]
        #expect(all.allSatisfy { $0.errorDescription?.isEmpty == false })
    }

    @Test("display names come from the file name")
    func names() {
        #expect(AudioImport.displayName(forFile: "Boss Fight.mp3") == "Boss Fight")
        #expect(AudioImport.displayName(forFile: ".wav") == "Untitled sound")
    }

    @Test("stored file names must be uuid.ext")
    func safeNames() {
        #expect(AudioImport.isSafeFileName("\(UUID().uuidString).wav"))
        #expect(!AudioImport.isSafeFileName("../../evil.wav"))
        #expect(!AudioImport.isSafeFileName("\(UUID().uuidString).sh"))
    }
}

@Suite("PackArchive")
struct PackArchiveTests {
    @Test("embeds only used user sounds and remaps them on import")
    func roundTrip() throws {
        let used = UserSound(name: "Roar", fileName: "\(UUID().uuidString).wav", duration: 1)
        let unused = UserSound(name: "Meh", fileName: "\(UUID().uuidString).wav", duration: 1)
        let missingID = UUID()
        let pack = CustomPack(name: "Dungeon", base: .arcade)
            .overriding(.macWakes, with: [.user(id: used.id), .system(name: "Hero")])
            .overriding(.macSleeps, with: [.user(id: missingID)])
        let archive = PackArchive(pack: pack, library: [used, unused])
        #expect(archive.sounds.map(\.id) == [used.id])

        let data = try JSONEncoder.soundControl.encode(archive)
        let decoded = try JSONDecoder.soundControl.decode(PackArchive.self, from: data)
        try decoded.validate()

        let newID = UUID()
        let imported = decoded.makePack(remapping: [used.id: newID])
        #expect(imported.name == "Dungeon")
        #expect(imported.base == .arcade)
        #expect(imported.overrides[.macWakes] == [.user(id: newID), .system(name: "Hero")])
        #expect(imported.overrides[.macSleeps] == nil)
        #expect(imported.id != pack.id)
    }

    @Test("validation rejects unsafe archives")
    func validation() throws {
        let pack = CustomPack(name: "X", base: .crystal)
        let good = try JSONEncoder.soundControl.encode(PackArchive(pack: pack, library: []))
        var json = try #require(JSONSerialization.jsonObject(with: good) as? [String: Any])

        json["formatVersion"] = 99
        let future = try JSONDecoder.soundControl.decode(PackArchive.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(throws: PackArchive.ImportError.unsupportedVersion(99)) { try future.validate() }

        json["formatVersion"] = 1
        json["name"] = "  "
        let unnamed = try JSONDecoder.soundControl.decode(PackArchive.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(throws: PackArchive.ImportError.emptyName) { try unnamed.validate() }

        json["name"] = "Ok"
        json["sounds"] = [["id": UUID().uuidString, "name": "bad", "fileName": "../x.wav", "duration": 1]]
        let unsafe = try JSONDecoder.soundControl.decode(PackArchive.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(throws: PackArchive.ImportError.invalidFileName("../x.wav")) { try unsafe.validate() }
        #expect(PackArchive.ImportError.emptyName.errorDescription != nil)

        let id = UUID()
        let entry: [String: Any] = ["id": id.uuidString, "name": "a", "fileName": "\(UUID().uuidString).wav", "duration": 1]
        json["sounds"] = [entry, entry]
        let duplicated = try JSONDecoder.soundControl.decode(PackArchive.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(throws: PackArchive.ImportError.duplicateSound(id)) { try duplicated.validate() }

        json["sounds"] = Array(repeating: entry, count: PackArchive.maximumSounds + 1)
        let huge = try JSONDecoder.soundControl.decode(PackArchive.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(throws: PackArchive.ImportError.tooManySounds(PackArchive.maximumSounds + 1)) { try huge.validate() }
        #expect(PackArchive.ImportError.tooManySounds(1).errorDescription != nil)
        #expect(PackArchive.ImportError.duplicateSound(id).errorDescription != nil)
    }
}

@Suite("ConfigStore")
struct ConfigStoreTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("sc-tests-\(UUID().uuidString)")
    }

    @Test("missing file loads defaults")
    func missing() {
        let loaded = ConfigStore(fileURL: folder.appendingPathComponent("config.json")).load()
        #expect(loaded.config == .default)
        #expect(loaded.recoveredFrom == nil)
    }

    @Test("save then load round-trips")
    func roundTrip() throws {
        let store = ConfigStore(fileURL: folder.appendingPathComponent("config.json"))
        let config = AppConfig.default.withMasterVolume(0.33)
        try store.save(config)
        #expect(store.load().config == config)
        try? FileManager.default.removeItem(at: folder)
    }

    @Test("corrupt file is moved aside, not overwritten")
    func corrupt() throws {
        let url = folder.appendingPathComponent("config.json")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: url)
        let loaded = ConfigStore(fileURL: url).load(now: Date(timeIntervalSince1970: 42))
        #expect(loaded.config == .default)
        let backup = try #require(loaded.recoveredFrom)
        #expect(backup.lastPathComponent == "config.corrupt-42.json")
        #expect(FileManager.default.fileExists(atPath: backup.path))
        #expect(!FileManager.default.fileExists(atPath: url.path))
        try? FileManager.default.removeItem(at: folder)
    }

    @Test("write failure surfaces a typed error")
    func writeFailure() {
        let store = ConfigStore(fileURL: URL(fileURLWithPath: "/dev/null/nope/config.json"))
        #expect(throws: ConfigStoreError.self) { try store.save(.default) }
        #expect(ConfigStoreError.writeFailed("x").errorDescription?.contains("x") == true)
        #expect(ConfigStore.applicationSupport().lastPathComponent == "SoundControl")
    }
}
