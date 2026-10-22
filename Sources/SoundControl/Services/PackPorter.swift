import Foundation
import SoundControlCore

/// Writes and reads `.soundpack` folders: `pack.json` plus a `sounds/` folder.
struct PackPorter {
    let soundStore: UserSoundStore

    enum PortError: Error, LocalizedError {
        case unreadable(String)
        case invalid(PackArchive.ImportError)
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case let .unreadable(reason): "Could not read the pack: \(reason)"
            case let .invalid(error): error.localizedDescription
            case let .writeFailed(reason): "Could not export the pack: \(reason)"
            }
        }
    }

    func export(_ pack: CustomPack, library: [UserSound], to destination: URL) throws(PortError) {
        let archive = PackArchive(pack: pack, library: library)
        let soundsFolder = destination.appendingPathComponent(PackArchive.soundsFolder, isDirectory: true)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.createDirectory(at: soundsFolder, withIntermediateDirectories: true)
            for sound in library where archive.sounds.contains(where: { $0.id == sound.id }) {
                try FileManager.default.copyItem(at: soundStore.url(for: sound),
                                                 to: soundsFolder.appendingPathComponent(sound.fileName))
            }
            let data = try JSONEncoder.soundControl.encode(archive)
            try data.write(to: destination.appendingPathComponent(PackArchive.manifestName), options: .atomic)
        } catch {
            throw .writeFailed(error.localizedDescription)
        }
    }

    struct ImportResult {
        let pack: CustomPack
        let sounds: [UserSound]
        /// Sounds listed in the pack that could not be imported (their overrides are dropped).
        let skipped: [String]
    }

    func importPack(from folder: URL) throws(PortError) -> ImportResult {
        let archive: PackArchive
        do {
            let manifest = folder.appendingPathComponent(PackArchive.manifestName)
            let size = try manifest.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= PackArchive.maximumManifestBytes else {
                throw PortError.unreadable("pack.json is larger than \(PackArchive.maximumManifestBytes / 1024) KB")
            }
            let data = try Data(contentsOf: manifest)
            archive = try JSONDecoder.soundControl.decode(PackArchive.self, from: data)
        } catch {
            throw .unreadable(error.localizedDescription)
        }
        do {
            try archive.validate()
        } catch {
            throw .invalid(error)
        }
        let soundsFolder = folder.appendingPathComponent(PackArchive.soundsFolder, isDirectory: true)
        var imported: [(UUID, UserSound)] = []
        var skipped: [String] = []
        for sound in archive.sounds {
            let source = soundsFolder.appendingPathComponent(sound.fileName)
            do {
                imported.append((sound.id, try soundStore.importFile(at: source, name: sound.name)))
            } catch {
                skipped.append(error.localizedDescription)
            }
        }
        // validate() rejects duplicate ids; keep the first anyway so a bad file can never trap.
        let remap = Dictionary(imported.map { ($0.0, $0.1.id) }, uniquingKeysWith: { first, _ in first })
        return ImportResult(pack: archive.makePack(remapping: remap), sounds: imported.map(\.1), skipped: skipped)
    }
}
