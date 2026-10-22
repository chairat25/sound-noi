import Foundation

/// The `pack.json` inside a `.soundpack` folder: a custom pack plus the user sounds it
/// references, so a pack can be shared with another Mac.
public struct PackArchive: Codable, Equatable, Sendable {
    public static let formatVersion = 1
    public static let manifestName = "pack.json"
    public static let soundsFolder = "sounds"
    public static let fileExtension = "soundpack"
    public static let maximumSounds = 200
    public static let maximumManifestBytes = 1_048_576

    public struct Sound: Codable, Equatable, Sendable {
        public let id: UUID
        public let name: String
        public let fileName: String
        public let duration: TimeInterval
    }

    public let formatVersion: Int
    public let name: String
    public let base: BuiltInPack
    public let overrides: [TriggerID: [SoundRef]]
    public let sounds: [Sound]

    /// Builds an archive from a pack, embedding only the user sounds it actually uses.
    public init(pack: CustomPack, library: [UserSound]) {
        let usedIDs = Set(pack.overrides.values.flatMap { $0 }.compactMap { ref -> UUID? in
            if case let .user(id) = ref { return id }
            return nil
        })
        formatVersion = PackArchive.formatVersion
        name = pack.name
        base = pack.base
        overrides = pack.overrides
        sounds = library.filter { usedIDs.contains($0.id) }
            .map { Sound(id: $0.id, name: $0.name, fileName: $0.fileName, duration: $0.duration) }
    }

    public enum ImportError: Error, Equatable, LocalizedError {
        case unsupportedVersion(Int)
        case invalidFileName(String)
        case emptyName
        case duplicateSound(UUID)
        case tooManySounds(Int)

        public var errorDescription: String? {
            switch self {
            case let .unsupportedVersion(version): "This pack was made by a newer version (format \(version))."
            case let .invalidFileName(name): "The pack contains an unsafe file name: \(name)"
            case .emptyName: "The pack has no name."
            case let .duplicateSound(id): "The pack lists the same sound twice (\(id.uuidString))."
            case let .tooManySounds(count): "The pack has \(count) sounds; the limit is \(PackArchive.maximumSounds)."
            }
        }
    }

    /// Checks everything that comes from an untrusted file before it touches the disk.
    public func validate() throws(ImportError) {
        guard formatVersion <= PackArchive.formatVersion else { throw .unsupportedVersion(formatVersion) }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw .emptyName }
        guard sounds.count <= PackArchive.maximumSounds else { throw .tooManySounds(sounds.count) }
        if let bad = sounds.first(where: { !AudioImport.isSafeFileName($0.fileName) }) {
            throw .invalidFileName(bad.fileName)
        }
        var seen = Set<UUID>()
        for sound in sounds where !seen.insert(sound.id).inserted {
            throw .duplicateSound(sound.id)
        }
    }

    /// Rewrites user-sound references to the ids the sounds received on import.
    /// References to sounds missing from the archive are dropped.
    public func makePack(id: UUID = UUID(), remapping newIDs: [UUID: UUID]) -> CustomPack {
        let overrides = self.overrides.compactMapValues { refs -> [SoundRef]? in
            let mapped = refs.compactMap { ref -> SoundRef? in
                guard case let .user(oldID) = ref else { return ref }
                return newIDs[oldID].map { .user(id: $0) }
            }
            return mapped.isEmpty ? nil : mapped
        }
        return CustomPack(id: id, name: name, base: base, overrides: overrides)
    }
}

/// Rules for audio files the user brings in.
public enum AudioImport {
    public static let allowedExtensions: Set<String> = ["wav", "aif", "aiff", "aifc", "mp3", "m4a", "caf", "aac", "flac"]
    public static let maximumBytes = 25 * 1024 * 1024
    public static let maximumDuration: TimeInterval = 30

    public enum Rejection: Error, Equatable, LocalizedError {
        case unsupportedType(String)
        case tooLarge(Int)
        case tooLong(TimeInterval)
        case unreadable

        public var errorDescription: String? {
            switch self {
            case let .unsupportedType(ext): "“.\(ext)” files are not supported. Use WAV, AIFF, MP3, M4A, CAF or FLAC."
            case let .tooLarge(bytes): "File is \(bytes / 1_048_576) MB; the limit is \(AudioImport.maximumBytes / 1_048_576) MB."
            case let .tooLong(seconds): "Sound is \(Int(seconds)) s long; keep it under \(Int(AudioImport.maximumDuration)) s."
            case .unreadable: "This file could not be read as audio."
            }
        }
    }

    public static func check(fileExtension: String, bytes: Int, duration: TimeInterval?) throws(Rejection) {
        try check(fileExtension: fileExtension, bytes: bytes)
        try check(duration: duration)
    }

    /// Cheap checks to run before the file is opened as audio.
    public static func check(fileExtension: String, bytes: Int?) throws(Rejection) {
        let ext = fileExtension.lowercased()
        guard allowedExtensions.contains(ext) else { throw .unsupportedType(ext) }
        guard let bytes, bytes > 0 else { throw .unreadable }
        guard bytes <= maximumBytes else { throw .tooLarge(bytes) }
    }

    public static func check(duration: TimeInterval?) throws(Rejection) {
        guard let duration, duration > 0 else { throw .unreadable }
        guard duration <= maximumDuration else { throw .tooLong(duration) }
    }

    /// Display name from a file name: no extension, trimmed, never empty.
    public static func displayName(forFile fileName: String) -> String {
        // NSString treats ".wav" as a hidden file without an extension, so split manually.
        let withoutExtension = fileName.lastIndex(of: ".").map { String(fileName[..<$0]) } ?? fileName
        let stem = withoutExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        return stem.isEmpty ? "Untitled sound" : String(stem.prefix(60))
    }

    /// Stored files are named `<uuid>.<ext>`; reject anything that could escape the sounds folder.
    public static func isSafeFileName(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        let stem = (name as NSString).deletingPathExtension
        return UUID(uuidString: stem) != nil && allowedExtensions.contains(ext)
    }
}
