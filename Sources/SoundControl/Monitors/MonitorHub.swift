import Foundation
import SoundControlCore

/// Callbacks every monitor gets: fire a trigger, or report that it cannot run here.
struct MonitorSink {
    let emit: (TriggerID, String?) -> Void
    /// `nil` reason clears a previous report.
    let setUnavailable: (Set<TriggerID>, String?) -> Void
    let isEnabled: (TriggerID) -> Bool
}

/// One source of Mac events. Monitors start only while at least one of their triggers
/// is enabled, so unused features cost nothing and never ask for permissions.
@MainActor
protocol TriggerMonitor: AnyObject {
    var triggers: Set<TriggerID> { get }
    func start()
    func stop()
}

@MainActor
final class MonitorHub {
    private let monitors: [TriggerMonitor]
    private var running: Set<ObjectIdentifier> = []

    init(sink: MonitorSink, settings: @escaping () -> AppConfig) {
        monitors = [
            PowerMonitor(sink: sink, thresholds: { (settings().batteryLowPercent, settings().batteryCriticalPercent) }),
            WorkspaceMonitor(sink: sink),
            DistributedMonitor(sink: sink),
            DisplayMonitor(sink: sink),
            LidMonitor(sink: sink),
            ThermalMonitor(sink: sink),
            AudioDeviceMonitor(sink: sink),
            USBMonitor(sink: sink),
            BluetoothMonitor(sink: sink),
            NetworkMonitor(sink: sink),
            InputMonitor(sink: sink),
            ClipboardMonitor(sink: sink),
            DownloadsMonitor(sink: sink),
            ScreenshotMonitor(sink: sink),
            TrashMonitor(sink: sink),
            IdleMonitor(sink: sink, idleMinutes: { settings().idleMinutes }),
            ClockMonitor(sink: sink)
        ]
    }

    /// Starts and stops monitors to match the enabled triggers.
    func reconcile(enabled: Set<TriggerID>, isListening: Bool) {
        for monitor in monitors {
            let id = ObjectIdentifier(monitor)
            let shouldRun = isListening && !monitor.triggers.isDisjoint(with: enabled)
            if shouldRun, !running.contains(id) {
                monitor.start()
                running.insert(id)
            } else if !shouldRun, running.contains(id) {
                monitor.stop()
                running.remove(id)
            }
        }
    }

    /// Restart one family (e.g. after granting Input Monitoring).
    func restart(monitorFor trigger: TriggerID) {
        for monitor in monitors where monitor.triggers.contains(trigger) && running.contains(ObjectIdentifier(monitor)) {
            monitor.stop()
            monitor.start()
        }
    }
}
