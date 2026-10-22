import AppKit
import SoundControlCore

/// Base for monitors that just map notifications to triggers.
@MainActor
class NotificationMonitor {
    let sink: MonitorSink
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    init(sink: MonitorSink) {
        self.sink = sink
    }

    func observe(_ name: Notification.Name, on center: NotificationCenter, handler: @escaping (Notification) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { notification in
            MainActor.assumeIsolated { handler(notification) }
        }
        tokens.append((center, token))
    }

    func removeObservers() {
        tokens.forEach { center, token in center.removeObserver(token) }
        tokens = []
    }
}

/// Sleep/wake, sessions, apps, disks and Spaces from NSWorkspace.
@MainActor
final class WorkspaceMonitor: NotificationMonitor, TriggerMonitor {
    let triggers: Set<TriggerID> = [
        .macSleeps, .macWakes, .displaySleeps, .displayWakes, .sessionResumed, .sessionSwitchedAway, .shutdown,
        .appLaunched, .appQuit, .appSwitched, .diskMounted, .diskEjected, .spaceChanged
    ]

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        let simple: [(Notification.Name, TriggerID)] = [
            (NSWorkspace.willSleepNotification, .macSleeps),
            (NSWorkspace.didWakeNotification, .macWakes),
            (NSWorkspace.screensDidSleepNotification, .displaySleeps),
            (NSWorkspace.screensDidWakeNotification, .displayWakes),
            (NSWorkspace.sessionDidBecomeActiveNotification, .sessionResumed),
            (NSWorkspace.sessionDidResignActiveNotification, .sessionSwitchedAway),
            (NSWorkspace.willPowerOffNotification, .shutdown),
            (NSWorkspace.activeSpaceDidChangeNotification, .spaceChanged)
        ]
        for (name, trigger) in simple {
            observe(name, on: center) { [sink] _ in sink.emit(trigger, nil) }
        }
        let apps: [(Notification.Name, TriggerID)] = [
            (NSWorkspace.didLaunchApplicationNotification, .appLaunched),
            (NSWorkspace.didTerminateApplicationNotification, .appQuit),
            (NSWorkspace.didActivateApplicationNotification, .appSwitched)
        ]
        for (name, trigger) in apps {
            observe(name, on: center) { [sink] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.activationPolicy == .regular,
                      app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
                sink.emit(trigger, app.localizedName)
            }
        }
        let volumes: [(Notification.Name, TriggerID)] = [
            (NSWorkspace.didMountNotification, .diskMounted),
            (NSWorkspace.didUnmountNotification, .diskEjected)
        ]
        for (name, trigger) in volumes {
            observe(name, on: center) { [sink] notification in
                sink.emit(trigger, notification.userInfo?[NSWorkspace.localizedVolumeNameUserInfoKey] as? String)
            }
        }
    }

    func stop() {
        removeObservers()
    }
}

/// Lock screen, screen saver and appearance changes, broadcast system-wide.
@MainActor
final class DistributedMonitor: NotificationMonitor, TriggerMonitor {
    let triggers: Set<TriggerID> = [
        .screenLocked, .screenUnlocked, .screensaverStarted, .screensaverStopped, .darkModeOn, .darkModeOff
    ]
    private var wasDark: Bool?

    func start() {
        let center = DistributedNotificationCenter.default()
        let simple: [(String, TriggerID)] = [
            ("com.apple.screenIsLocked", .screenLocked),
            ("com.apple.screenIsUnlocked", .screenUnlocked),
            ("com.apple.screensaver.didstart", .screensaverStarted),
            ("com.apple.screensaver.didstop", .screensaverStopped)
        ]
        for (name, trigger) in simple {
            observe(Notification.Name(name), on: center) { [sink] _ in sink.emit(trigger, nil) }
        }
        wasDark = Self.isDark()
        observe(Notification.Name("AppleInterfaceThemeChangedNotification"), on: center) { [weak self] _ in
            // The preference is already written when the broadcast arrives.
            self?.appearanceChanged()
        }
    }

    func stop() {
        removeObservers()
    }

    private func appearanceChanged() {
        let isDark = Self.isDark()
        if let trigger = Edge.detect(previous: wasDark, current: isDark, rising: .darkModeOn, falling: .darkModeOff) {
            sink.emit(trigger, nil)
        }
        wasDark = isDark
    }

    /// Reads the global preference directly; NSApp may not exist yet and its appearance lags the broadcast.
    private static func isDark() -> Bool {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        let style = CFPreferencesCopyAppValue("AppleInterfaceStyle" as CFString, kCFPreferencesAnyApplication) as? String
        return style == "Dark"
    }
}

/// External displays, by counting screens after the configuration settles.
@MainActor
final class DisplayMonitor: NotificationMonitor, TriggerMonitor {
    let triggers: Set<TriggerID> = [.displayConnected, .displayDisconnected]
    private static let settleDelay: TimeInterval = 0.3
    private var screenCount = 0
    private var pending: DispatchWorkItem?

    func start() {
        screenCount = NSScreen.screens.count
        observe(NSApplication.didChangeScreenParametersNotification, on: .default) { [weak self] _ in
            self?.scheduleCheck()
        }
    }

    func stop() {
        pending?.cancel()
        removeObservers()
    }

    private func scheduleCheck() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.check() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: work)
    }

    private func check() {
        let count = NSScreen.screens.count
        defer { screenCount = count }
        guard count != screenCount else { return }
        sink.emit(count > screenCount ? .displayConnected : .displayDisconnected, "\(count) display(s)")
    }
}
