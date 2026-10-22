import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import SoundControlCore

/// Charger, battery levels and Low Power Mode.
@MainActor
final class PowerMonitor: TriggerMonitor {
    let triggers: Set<TriggerID> = [
        .chargerConnected, .chargerDisconnected, .batteryFull, .batteryLow, .batteryCritical, .lowPowerOn, .lowPowerOff
    ]
    private let sink: MonitorSink
    private let thresholds: () -> (Int, Int)
    private var source: CFRunLoopSource?
    /// Fires the moment the adapter is plugged or unplugged; the general source can lag behind.
    private var adapterSource: CFRunLoopSource?
    private var lowPowerObserver: NSObjectProtocol?
    private var lastSnapshot: BatterySnapshot?
    private var lastLowPower: Bool?

    init(sink: MonitorSink, thresholds: @escaping () -> (Int, Int)) {
        self.sink = sink
        self.thresholds = thresholds
    }

    func start() {
        lastSnapshot = Self.readSnapshot()
        lastLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        if lastSnapshot == nil {
            sink.setUnavailable([.batteryFull, .batteryLow, .batteryCritical], "This Mac has no battery")
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let loopSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.powerSourcesChanged() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), loopSource, .defaultMode)
            source = loopSource
        }
        if let adapter = IOPSCreateLimitedPowerNotification({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.powerSourcesChanged() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), adapter, .defaultMode)
            adapterSource = adapter
        }
        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.lowPowerChanged() }
        }
    }

    func stop() {
        for loopSource in [source, adapterSource].compactMap({ $0 }) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), loopSource, .defaultMode)
            CFRunLoopSourceInvalidate(loopSource)
        }
        source = nil
        adapterSource = nil
        lowPowerObserver.map(NotificationCenter.default.removeObserver)
        lowPowerObserver = nil
    }

    private func powerSourcesChanged() {
        // Both sources can fire for one plug; BatteryTracker only reports real changes, so no double sound.
        guard source != nil, let snapshot = Self.readSnapshot() else { return }
        let (low, critical) = thresholds()
        let events = BatteryTracker.events(from: lastSnapshot, to: snapshot, lowPercent: low, criticalPercent: critical)
        lastSnapshot = snapshot
        events.forEach { sink.emit($0, "\(snapshot.percent)%") }
    }

    private func lowPowerChanged() {
        let current = ProcessInfo.processInfo.isLowPowerModeEnabled
        if let trigger = Edge.detect(previous: lastLowPower, current: current, rising: .lowPowerOn, falling: .lowPowerOff) {
            sink.emit(trigger, nil)
        }
        lastLowPower = current
    }

    /// nil when the Mac has no internal battery.
    static func readSnapshot() -> BatterySnapshot? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            return BatterySnapshot(
                isOnAC: providing == kIOPMACPowerKey,
                percent: Int((Double(current) / Double(maximum) * 100).rounded()),
                isCharged: description[kIOPSIsChargedKey] as? Bool ?? false
            )
        }
        return nil
    }
}

/// Thermal pressure ("Mac is heating up").
@MainActor
final class ThermalMonitor: TriggerMonitor {
    let triggers: Set<TriggerID> = [.thermalHot, .thermalCooled]
    private let sink: MonitorSink
    private var observer: NSObjectProtocol?
    private var wasHot: Bool?

    init(sink: MonitorSink) {
        self.sink = sink
    }

    func start() {
        wasHot = ThermalLevel.isHot(rawState: ProcessInfo.processInfo.thermalState.rawValue)
        observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.changed() }
        }
    }

    func stop() {
        observer.map(NotificationCenter.default.removeObserver)
        observer = nil
    }

    private func changed() {
        let isHot = ThermalLevel.isHot(rawState: ProcessInfo.processInfo.thermalState.rawValue)
        if let trigger = Edge.detect(previous: wasHot, current: isHot, rising: .thermalHot, falling: .thermalCooled) {
            sink.emit(trigger, nil)
        }
        wasHot = isHot
    }
}

/// MacBook lid, via the power-management root domain's clamshell messages.
@MainActor
final class LidMonitor: TriggerMonitor {
    let triggers: Set<TriggerID> = [.lidClosed, .lidOpened]
    /// iokit_family_msg(sub_iokit_powermanagement, 0x100); the C macro is not imported into Swift.
    private static let clamshellStateChange: UInt32 = 0xE003_4100
    private static let clamshellClosedBit = 1

    private let sink: MonitorSink
    private var port: IONotificationPortRef?
    private var notifier: io_object_t = 0
    private var rootDomain: io_service_t = 0
    private var wasClosed: Bool?

    init(sink: MonitorSink) {
        self.sink = sink
    }

    func start() {
        rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != 0, let closed = readClosed() else {
            sink.setUnavailable(triggers, "This Mac has no lid")
            return
        }
        wasClosed = closed
        port = IONotificationPortCreate(kIOMainPortDefault)
        guard let port else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOServiceAddInterestNotification(port, rootDomain, kIOGeneralInterest, { context, _, messageType, argument in
            guard let context, messageType == LidMonitor.clamshellStateChange else { return }
            let isClosed = (Int(bitPattern: argument) & LidMonitor.clamshellClosedBit) != 0
            let monitor = Unmanaged<LidMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.update(closed: isClosed) }
        }, context, &notifier)
    }

    func stop() {
        if notifier != 0 { IOObjectRelease(notifier) }
        if rootDomain != 0 { IOObjectRelease(rootDomain) }
        if let port {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
            IONotificationPortDestroy(port)
        }
        notifier = 0
        rootDomain = 0
        port = nil
    }

    private func update(closed: Bool) {
        if let trigger = Edge.detect(previous: wasClosed, current: closed, rising: .lidClosed, falling: .lidOpened) {
            sink.emit(trigger, nil)
        }
        wasClosed = closed
    }

    private func readClosed() -> Bool? {
        IORegistryEntryCreateCFProperty(rootDomain, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool
    }
}
