import Foundation

/// Decodes one element and remembers whether it worked, so arrays can skip bad entries.
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(Value.self)
    }
}

extension KeyedDecodingContainer {
    /// An array where entries that fail to decode (e.g. written by a newer version) are dropped.
    func decodeLossyArray<Element: Decodable>(_ type: Element.Type, forKey key: Key) -> [Element]? {
        (try? decodeIfPresent([Lossy<Element>].self, forKey: key))?.flatMap { $0.compactMap(\.value) }
    }

    /// A trigger-keyed dictionary where unknown trigger names and bad values are dropped.
    func decodeLossyTriggerMap<Value: Decodable>(_ type: Value.Type, forKey key: Key) -> [TriggerID: Value]? {
        guard let raw = try? decodeIfPresent([String: Lossy<Value>].self, forKey: key) else { return nil }
        return raw.reduce(into: [:]) { result, entry in
            guard let trigger = TriggerID(rawValue: entry.key), let value = entry.value.value else { return }
            result[trigger] = value
        }
    }
}
