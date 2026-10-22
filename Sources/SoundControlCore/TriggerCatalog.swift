import Foundation

/// Static description of a trigger: how it looks, what it sounds like by default.
public struct TriggerInfo: Sendable, Identifiable {
    public let id: TriggerID
    public let title: String
    public let detail: String
    public let category: TriggerCategory
    /// SF Symbol name shown in the UI.
    public let symbol: String
    public let motif: Motif
    public let isRecommended: Bool
    public let permission: PermissionKind
    /// Minimum seconds between two plays of this trigger (guards against bursts).
    public let cooldown: TimeInterval

    /// Fires many times a minute (keys, clicks, volume); kept out of the activity log.
    public var isChatty: Bool { cooldown < 0.2 }
}

public enum TriggerCatalog {
    public static let all: [TriggerInfo] = power + system + screen + apps + devices + audio + network + input + files + time

    private static let byID: [TriggerID: TriggerInfo] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static func info(for id: TriggerID) -> TriggerInfo {
        // Every TriggerID is registered; the catalog test enforces it.
        byID[id]!
    }

    public static func triggers(in category: TriggerCategory) -> [TriggerInfo] {
        all.filter { $0.category == category }
    }

    public static var recommended: Set<TriggerID> {
        Set(all.filter(\.isRecommended).map(\.id))
    }

    private static func make(
        _ id: TriggerID, _ title: String, _ detail: String, _ category: TriggerCategory,
        _ symbol: String, _ motif: Motif, recommended: Bool = false,
        permission: PermissionKind = .none, cooldown: TimeInterval = 0.5
    ) -> TriggerInfo {
        TriggerInfo(id: id, title: title, detail: detail, category: category, symbol: symbol,
                    motif: motif, isRecommended: recommended, permission: permission, cooldown: cooldown)
    }

    private static let power: [TriggerInfo] = [
        make(.chargerConnected, "Charger connected", "Power adapter plugged in", .power, "powerplug.fill", .rise, recommended: true),
        make(.chargerDisconnected, "Charger disconnected", "Running on battery", .power, "powerplug", .fall, recommended: true),
        make(.batteryFull, "Battery fully charged", "Reached 100% on the charger", .power, "battery.100percent.bolt", .success, recommended: true),
        make(.batteryLow, "Battery low", "Drops below your low threshold", .power, "battery.25percent", .warning, recommended: true),
        make(.batteryCritical, "Battery critical", "Drops below your critical threshold", .power, "battery.0percent", .alarm, recommended: true),
        make(.lowPowerOn, "Low Power Mode on", "Energy saver switched on", .power, "leaf.fill", .doubleDown),
        make(.lowPowerOff, "Low Power Mode off", "Energy saver switched off", .power, "leaf", .doubleUp)
    ]

    private static let system: [TriggerInfo] = [
        make(.appStarted, "You log in", "Sound Control starts with your session", .system, "sparkles", .ascend, recommended: true),
        make(.sessionResumed, "Switched back to you", "Fast user switching returns to this account", .system, "person.crop.circle.badge.checkmark", .doubleUp),
        make(.sessionSwitchedAway, "Switched to another user", "Fast user switching leaves this account", .system, "person.2.circle", .doubleDown),
        make(.macSleeps, "Mac goes to sleep", "System sleep starts", .system, "moon.zzz.fill", .descend, recommended: true),
        make(.macWakes, "Mac wakes up", "System wakes from sleep", .system, "sun.max.fill", .ascend, recommended: true),
        make(.shutdown, "Shut down or restart", "Mac is powering off or logging out", .system, "power", .descend),
        make(.lidClosed, "Lid closed", "MacBook lid shut (clamshell)", .system, "laptopcomputer.slash", .thud),
        make(.lidOpened, "Lid opened", "MacBook lid opened", .system, "laptopcomputer", .pop),
        make(.thermalHot, "Mac is heating up", "Thermal pressure is serious or critical", .system, "thermometer.sun.fill", .warning),
        make(.thermalCooled, "Mac cooled down", "Thermal pressure back to normal", .system, "thermometer.snowflake", .doubleUp)
    ]

    private static let screen: [TriggerInfo] = [
        make(.screenLocked, "Screen locked", "Lock screen shown", .screen, "lock.fill", .doubleDown, recommended: true),
        make(.screenUnlocked, "Screen unlocked", "Welcome back to the desktop", .screen, "lock.open.fill", .doubleUp, recommended: true),
        make(.screensaverStarted, "Screen saver starts", "Screen saver kicks in", .screen, "sparkles.tv", .whoosh),
        make(.screensaverStopped, "Screen saver stops", "Screen saver dismissed", .screen, "tv", .pop),
        make(.displaySleeps, "Display sleeps", "Screens turn off", .screen, "display", .descend),
        make(.displayWakes, "Display wakes", "Screens turn on", .screen, "display", .ascend),
        make(.displayConnected, "Display connected", "External monitor plugged in", .screen, "display.2", .rise, recommended: true),
        make(.displayDisconnected, "Display disconnected", "External monitor unplugged", .screen, "rectangle.on.rectangle.slash", .fall, recommended: true),
        make(.darkModeOn, "Dark mode on", "Appearance switched to dark", .screen, "moon.fill", .doubleDown),
        make(.darkModeOff, "Light mode on", "Appearance switched to light", .screen, "sun.min.fill", .doubleUp),
        make(.spaceChanged, "Space changed", "Swiped to another desktop or full-screen app", .screen, "rectangle.3.group", .whoosh, cooldown: 0.25)
    ]

    private static let apps: [TriggerInfo] = [
        make(.appLaunched, "App launched", "Any regular app opens", .apps, "app.badge.checkmark", .pop),
        make(.appQuit, "App quit", "Any regular app closes", .apps, "xmark.app", .tap),
        make(.appSwitched, "Switched app", "Another app comes to the front", .apps, "square.on.square", .tick, cooldown: 0.15)
    ]

    private static let devices: [TriggerInfo] = [
        make(.usbConnected, "USB device connected", "Something plugged into a USB port", .devices, "cable.connector", .rise, recommended: true),
        make(.usbDisconnected, "USB device disconnected", "Something unplugged from a USB port", .devices, "cable.connector.slash", .fall, recommended: true),
        make(.diskMounted, "Disk mounted", "Drive, SD card or disk image appears", .devices, "externaldrive.fill.badge.plus", .doubleUp),
        make(.diskEjected, "Disk ejected", "Drive or disk image goes away", .devices, "eject.fill", .doubleDown),
        make(.bluetoothConnected, "Bluetooth connected", "AirPods, keyboard or mouse connects", .devices, "dot.radiowaves.left.and.right", .rise, permission: .bluetooth),
        make(.bluetoothDisconnected, "Bluetooth disconnected", "A Bluetooth device drops", .devices, "antenna.radiowaves.left.and.right.slash", .fall, permission: .bluetooth),
        make(.audioOutputChanged, "Audio output changed", "Headphones or speakers switched", .devices, "headphones", .chime)
    ]

    private static let audio: [TriggerInfo] = [
        make(.volumeChanged, "Volume changed", "System output volume moved", .audio, "speaker.wave.2.fill", .tick, cooldown: 0.12),
        make(.muted, "Muted", "System output muted", .audio, "speaker.slash.fill", .doubleDown),
        make(.unmuted, "Unmuted", "System output unmuted", .audio, "speaker.wave.3.fill", .doubleUp)
    ]

    private static let network: [TriggerInfo] = [
        make(.internetConnected, "Internet connected", "Network becomes reachable", .network, "wifi", .rise, recommended: true),
        make(.internetLost, "Internet lost", "Network becomes unreachable", .network, "wifi.slash", .fall, recommended: true),
        make(.networkChanged, "Network changed", "Switched between Wi-Fi, Ethernet or hotspot", .network, "network", .chime)
    ]

    private static let input: [TriggerInfo] = [
        make(.keyTyped, "Key typed", "Any letter, number or symbol key", .input, "keyboard", .click, permission: .inputMonitoring, cooldown: 0),
        make(.returnKey, "Return key", "Return / Enter pressed", .input, "return", .tap, permission: .inputMonitoring, cooldown: 0),
        make(.deleteKey, "Delete key", "Backspace / Delete pressed", .input, "delete.left", .tick, permission: .inputMonitoring, cooldown: 0),
        make(.spaceKey, "Space bar", "Space bar pressed", .input, "space", .thud, permission: .inputMonitoring, cooldown: 0),
        make(.mouseClick, "Mouse click", "Left click anywhere", .input, "cursorarrow.click", .click, permission: .inputMonitoring, cooldown: 0),
        make(.rightClick, "Right click", "Secondary click anywhere", .input, "cursorarrow.click.2", .tap, permission: .inputMonitoring, cooldown: 0),
        make(.capsLockOn, "Caps Lock on", "Caps Lock engaged", .input, "capslock.fill", .doubleUp, permission: .inputMonitoring),
        make(.capsLockOff, "Caps Lock off", "Caps Lock released", .input, "capslock", .doubleDown, permission: .inputMonitoring)
    ]

    private static let files: [TriggerInfo] = [
        make(.screenshotTaken, "Screenshot taken", "A new screen capture is saved", .files, "camera.viewfinder", .pop, recommended: true),
        make(.fileDownloaded, "Download finished", "A new file lands in Downloads", .files, "arrow.down.circle.fill", .success, recommended: true),
        make(.clipboardCopied, "Copied to clipboard", "Something new is copied", .files, "doc.on.clipboard", .tick, cooldown: 0.2),
        make(.trashChanged, "Trash changed", "Files moved to or emptied from the Trash", .files, "trash.fill", .thud)
    ]

    private static let time: [TriggerInfo] = [
        make(.hourlyChime, "Every hour", "Chime at the top of each hour", .time, "clock.fill", .toll),
        make(.halfHourChime, "Every half hour", "Soft chime at :30", .time, "clock", .chime),
        make(.idleStarted, "You stepped away", "No input for your idle time", .time, "figure.walk.departure", .descend),
        make(.idleReturned, "Welcome back", "Input again after being idle", .time, "figure.walk.arrival", .sparkle)
    ]
}
