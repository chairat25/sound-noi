import Foundation

public enum ConfigStoreError: Error, Equatable, LocalizedError {
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .writeFailed(reason): "Could not save settings: \(reason)"
        }
    }
}

/// The result of loading settings from disk.
public struct LoadedConfig: Sendable {
    public let config: AppConfig
    /// Set when an unreadable file was moved aside and defaults were used instead.
    public let recoveredFrom: URL?
}

/// Reads and writes `config.json`. A corrupt file is never overwritten silently:
/// it is renamed to `config.corrupt-<timestamp>.json` so the user can recover it.
public struct ConfigStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func applicationSupport(appFolder: String = "SoundControl") -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(appFolder, isDirectory: true)
    }

    public func load(now: Date = Date()) -> LoadedConfig {
        guard let data = try? Data(contentsOf: fileURL) else {
            return LoadedConfig(config: .default, recoveredFrom: nil)
        }
        do {
            let config = try JSONDecoder.soundControl.decode(AppConfig.self, from: data)
            return LoadedConfig(config: config, recoveredFrom: nil)
        } catch {
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("config.corrupt-\(Int(now.timeIntervalSince1970)).json")
            let moved = (try? FileManager.default.moveItem(at: fileURL, to: backup)) != nil
            return LoadedConfig(config: .default, recoveredFrom: moved ? backup : nil)
        }
    }

    public func save(_ config: AppConfig) throws(ConfigStoreError) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONEncoder.soundControl.encode(config)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw .writeFailed(error.localizedDescription)
        }
    }
}

extension JSONEncoder {
    public static var soundControl: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    public static var soundControl: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
