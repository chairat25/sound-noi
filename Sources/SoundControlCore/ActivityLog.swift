import Foundation

public struct ActivityEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let trigger: TriggerID
    public let date: Date
    /// nil when the sound played; otherwise why it was skipped.
    public let skipReason: SkipReason?
    public let soundName: String?
    /// Optional context such as the app or device name.
    public let context: String?

    public init(id: UUID = UUID(), trigger: TriggerID, date: Date, skipReason: SkipReason?,
                soundName: String?, context: String?) {
        self.id = id
        self.trigger = trigger
        self.date = date
        self.skipReason = skipReason
        self.soundName = soundName
        self.context = context
    }

    public var didPlay: Bool { skipReason == nil }
}

/// Bounded, newest-first history of what happened.
public struct ActivityLog: Equatable, Sendable {
    public static let capacity = 200

    public let entries: [ActivityEntry]

    public init(entries: [ActivityEntry] = []) {
        self.entries = Array(entries.prefix(ActivityLog.capacity))
    }

    public func appending(_ entry: ActivityEntry) -> ActivityLog {
        ActivityLog(entries: [entry] + entries)
    }

    public func playCount(since date: Date) -> Int {
        entries.filter { $0.didPlay && $0.date >= date }.count
    }
}
