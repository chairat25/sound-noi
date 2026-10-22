import Foundation

/// Turns a boolean state change into the matching trigger. The first observation
/// (no previous value) never fires, so launching the app is silent.
public enum Edge {
    public static func detect(previous: Bool?, current: Bool, rising: TriggerID, falling: TriggerID) -> TriggerID? {
        guard let previous, previous != current else { return nil }
        return current ? rising : falling
    }
}

/// A reading of the power source.
public struct BatterySnapshot: Equatable, Sendable {
    public let isOnAC: Bool
    public let percent: Int
    public let isCharged: Bool

    public init(isOnAC: Bool, percent: Int, isCharged: Bool) {
        self.isOnAC = isOnAC
        self.percent = percent
        self.isCharged = isCharged
    }

    var isFull: Bool { isOnAC && (isCharged || percent >= 100) }
}

public enum BatteryTracker {
    public static func events(from previous: BatterySnapshot?, to current: BatterySnapshot,
                              lowPercent: Int, criticalPercent: Int) -> [TriggerID] {
        guard let previous else { return [] }
        var events: [TriggerID] = []
        if let plug = Edge.detect(previous: previous.isOnAC, current: current.isOnAC,
                                  rising: .chargerConnected, falling: .chargerDisconnected) {
            events.append(plug)
        }
        if !previous.isFull && current.isFull {
            events.append(.batteryFull)
        }
        if !current.isOnAC {
            let crossed = { (threshold: Int) in previous.percent > threshold && current.percent <= threshold }
            // Falling through both thresholds at once (e.g. after sleep) only needs the louder warning.
            if crossed(criticalPercent) {
                events.append(.batteryCritical)
            } else if crossed(lowPercent) {
                events.append(.batteryLow)
            }
        }
        return events
    }
}

/// Tracks "away from keyboard" based on seconds since the last input event.
public struct IdleTracker: Equatable, Sendable {
    /// Input within this many seconds counts as "back".
    public static let returnWindow: TimeInterval = 3

    public let isIdle: Bool

    public init(isIdle: Bool = false) {
        self.isIdle = isIdle
    }

    public func update(secondsSinceInput: TimeInterval, idleThreshold: TimeInterval) -> (IdleTracker, TriggerID?) {
        if !isIdle, secondsSinceInput >= idleThreshold {
            return (IdleTracker(isIdle: true), .idleStarted)
        }
        if isIdle, secondsSinceInput < IdleTracker.returnWindow {
            return (IdleTracker(isIdle: false), .idleReturned)
        }
        return (self, nil)
    }
}

public enum ClockChime {
    /// Gaps longer than this (the Mac slept) never chime retroactively. Comfortably above the poll interval.
    public static let maximumGap: TimeInterval = 60

    /// The chime due for a boundary crossed in `(last, now]`, if any.
    public static func chime(from last: Date, to now: Date, calendar: Calendar = .current) -> TriggerID? {
        guard now > last, now.timeIntervalSince(last) <= maximumGap else { return nil }
        guard let boundary = nextHalfHour(after: last, calendar: calendar), boundary <= now else { return nil }
        return calendar.component(.minute, from: boundary) == 0 ? .hourlyChime : .halfHourChime
    }

    static func nextHalfHour(after date: Date, calendar: Calendar) -> Date? {
        let minute = calendar.component(.minute, from: date)
        let targetMinute = minute < 30 ? 30 : 0
        return calendar.nextDate(after: date, matching: DateComponents(minute: targetMinute, second: 0),
                                 matchingPolicy: .nextTime)
    }
}

public enum ThermalLevel {
    /// `ProcessInfo.ThermalState.rawValue`: 0 nominal, 1 fair, 2 serious, 3 critical.
    public static func isHot(rawState: Int) -> Bool { rawState >= 2 }
}

public enum DownloadFilter {
    static let partialExtensions: Set<String> = [
        "crdownload", "download", "part", "partial", "tmp", "opdownload", "filepart", "aria2"
    ]

    public static func isFinishedDownload(_ name: String) -> Bool {
        guard !name.hasPrefix("."), !name.isEmpty else { return false }
        let ext = (name as NSString).pathExtension.lowercased()
        return !partialExtensions.contains(ext)
    }

    /// Finished files present now that were not there before.
    public static func newDownloads(before: Set<String>, after: Set<String>) -> [String] {
        after.subtracting(before).filter(isFinishedDownload).sorted()
    }
}
