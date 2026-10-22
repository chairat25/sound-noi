import Foundation
import SoundControlCore

/// Copies imported audio into the app's own folder so sounds survive the original
/// file being moved or deleted.
struct UserSoundStore {
    let folder: URL

    enum StoreError: Error, LocalizedError {
        case rejected(String, AudioImport.Rejection)
        case copyFailed(String, String)

        var errorDescription: String? {
            switch self {
            case let .rejected(name, reason): "\(name): \(reason.localizedDescription)"
            case let .copyFailed(name, reason): "\(name): could not copy file (\(reason))"
            }
        }
    }

    /// Validates and copies one file. `name` overrides the display name (used by pack import).
    func importFile(at source: URL, id: UUID = UUID(), name: String? = nil) throws(StoreError) -> UserSound {
        let displayName = name ?? AudioImport.displayName(forFile: source.lastPathComponent)
        let values = try? source.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey, .isRegularFileKey])
        let ext = source.pathExtension.lowercased()
        // Symlinks would be copied as links pointing outside the sounds folder.
        guard values?.isSymbolicLink != true, values?.isRegularFile == true else {
            throw .rejected(displayName, .unreadable)
        }
        do {
            try AudioImport.check(fileExtension: ext, bytes: values?.fileSize)
            try AudioImport.check(duration: SoundLibrary.duration(of: source))
        } catch {
            throw .rejected(displayName, error)
        }
        let fileName = "\(id.uuidString).\(ext)"
        let destination = folder.appendingPathComponent(fileName)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            throw .copyFailed(displayName, error.localizedDescription)
        }
        return UserSound(id: id, name: displayName, fileName: fileName,
                         duration: SoundLibrary.duration(of: destination) ?? 0)
    }

    func delete(_ sound: UserSound) {
        guard AudioImport.isSafeFileName(sound.fileName) else { return }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(sound.fileName))
    }

    func url(for sound: UserSound) -> URL {
        folder.appendingPathComponent(sound.fileName)
    }
}
