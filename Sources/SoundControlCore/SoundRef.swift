import Foundation

/// A pointer to one playable sound. Persisted as a compact string
/// (`synth:crystal:rise:0`, `system:Glass`, `user:<uuid>`).
public enum SoundRef: Hashable, Sendable {
    case synth(pack: BuiltInPack, motif: Motif, take: Int)
    case system(name: String)
    case user(id: UUID)

    public init?(string: String) {
        let parts = string.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        switch parts.first {
        case "synth" where parts.count == 4:
            guard let pack = BuiltInPack(rawValue: parts[1]), let motif = Motif(rawValue: parts[2]),
                  let take = Int(parts[3]), (0..<Motif.takeCount).contains(take) else { return nil }
            self = .synth(pack: pack, motif: motif, take: take)
        case "system" where parts.count == 2:
            guard SoundRef.isSafeSystemName(parts[1]) else { return nil }
            self = .system(name: parts[1])
        case "user" where parts.count == 2:
            guard let id = UUID(uuidString: parts[1]) else { return nil }
            self = .user(id: id)
        default:
            return nil
        }
    }

    public var string: String {
        switch self {
        case let .synth(pack, motif, take): "synth:\(pack.rawValue):\(motif.rawValue):\(take)"
        case let .system(name): "system:\(name)"
        case let .user(id): "user:\(id.uuidString)"
        }
    }

    /// System sound names become file names under /System/Library/Sounds; reject anything path-like.
    static func isSafeSystemName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 64
            && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" || $0 == "_" }
    }
}

extension SoundRef: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let ref = SoundRef(string: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown sound reference '\(raw)'")
        }
        self = ref
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string)
    }
}
