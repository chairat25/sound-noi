import AppKit
import CoreGraphics
import Network
import SoundControlCore

/// Base for monitors that sample something on a timer.
@MainActor
class PollingMonitor {
    let sink: MonitorSink
    private let interval: TimeInterval
    private var timer: Timer?

    init(sink: MonitorSink, interval: TimeInterval) {
        self.sink = sink
        self.interval = interval
    }

    func start() {
        prepare()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer?.tolerance = interval * 0.2
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func prepare() {}
    func poll() {}
}

/// "Copied to clipboard": the pasteboard's change count moves on every copy.
/// The clipboard *contents* are never read.
@MainActor
final class ClipboardMonitor: PollingMonitor, TriggerMonitor {
    let triggers: Set<TriggerID> = [.clipboardCopied]
    private var changeCount = 0

    init(sink: MonitorSink) {
        // changeCount is a cheap integer read, so poll fast enough to feel instant.
        super.init(sink: sink, interval: 0.12)
    }

    override func prepare() {
        changeCount = NSPasteboard.general.changeCount
    }

    override func poll() {
        let current = NSPasteboard.general.changeCount
        guard current != changeCount else { return }
        changeCount = current
        sink.emit(.clipboardCopied, nil)
    }
}

/// Away-from-keyboard detection using seconds since the last input event (no permission needed).
@MainActor
final class IdleMonitor: PollingMonitor, TriggerMonitor {
    let triggers: Set<TriggerID> = [.idleStarted, .idleReturned]
    private let idleMinutes: () -> Int
    private var tracker = IdleTracker()

    init(sink: MonitorSink, idleMinutes: @escaping () -> Int) {
        self.idleMinutes = idleMinutes
        super.init(sink: sink, interval: 1.0)
    }

    override func prepare() {
        tracker = IdleTracker()
    }

    override func poll() {
        let anyInput = CGEventType(rawValue: UInt32.max)!
        let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        let (next, trigger) = tracker.update(secondsSinceInput: seconds, idleThreshold: TimeInterval(idleMinutes() * 60))
        tracker = next
        trigger.map { sink.emit($0, nil) }
    }
}

/// Hourly and half-hourly chimes.
@MainActor
final class ClockMonitor: PollingMonitor, TriggerMonitor {
    let triggers: Set<TriggerID> = [.hourlyChime, .halfHourChime]
    private var lastCheck = Date()

    init(sink: MonitorSink) {
        super.init(sink: sink, interval: 10)
    }

    override func prepare() {
        lastCheck = Date()
    }

    override func poll() {
        let now = Date()
        defer { lastCheck = now }
        guard let chime = ClockChime.chime(from: lastCheck, to: now) else { return }
        sink.emit(chime, now.formatted(date: .omitted, time: .shortened))
    }
}

/// Reachability and interface changes via NWPathMonitor.
@MainActor
final class NetworkMonitor: TriggerMonitor {
    let triggers: Set<TriggerID> = [.internetConnected, .internetLost, .networkChanged]
    private let sink: MonitorSink
    private var monitor: NWPathMonitor?
    private var wasOnline: Bool?
    private var lastInterface: NWInterface.InterfaceType?

    init(sink: MonitorSink) {
        self.sink = sink
    }

    func start() {
        wasOnline = nil
        lastInterface = nil
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            MainActor.assumeIsolated { self?.update(path) }
        }
        monitor.start(queue: .main)
        self.monitor = monitor
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
    }

    private func update(_ path: NWPath) {
        let isOnline = path.status == .satisfied
        let interface = Self.primaryInterface(path)
        defer {
            wasOnline = isOnline
            lastInterface = interface
        }
        if let trigger = Edge.detect(previous: wasOnline, current: isOnline, rising: .internetConnected, falling: .internetLost) {
            sink.emit(trigger, interface.map(Self.describe))
            return
        }
        if isOnline, wasOnline == true, let interface, let lastInterface, interface != lastInterface {
            sink.emit(.networkChanged, Self.describe(interface))
        }
    }

    private static func primaryInterface(_ path: NWPath) -> NWInterface.InterfaceType? {
        [.wifi, .wiredEthernet, .cellular, .other].first { path.usesInterfaceType($0) }
    }

    private static func describe(_ type: NWInterface.InterfaceType) -> String {
        switch type {
        case .wifi: "Wi-Fi"
        case .wiredEthernet: "Ethernet"
        case .cellular: "Cellular"
        default: "Other network"
        }
    }
}
