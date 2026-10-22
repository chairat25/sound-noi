import Foundation

/// Every Mac moment the app can react to. Raw values are persisted — never rename them.
public enum TriggerID: String, CaseIterable, Codable, Sendable, Hashable {
    // Power
    case chargerConnected, chargerDisconnected, batteryFull, batteryLow, batteryCritical
    case lowPowerOn, lowPowerOff
    // System
    case appStarted, sessionResumed, sessionSwitchedAway, macSleeps, macWakes, shutdown
    case lidClosed, lidOpened, thermalHot, thermalCooled
    // Screen
    case screenLocked, screenUnlocked, screensaverStarted, screensaverStopped
    case displaySleeps, displayWakes, displayConnected, displayDisconnected
    case darkModeOn, darkModeOff, spaceChanged
    // Apps
    case appLaunched, appQuit, appSwitched
    // Devices
    case usbConnected, usbDisconnected, diskMounted, diskEjected
    case bluetoothConnected, bluetoothDisconnected, audioOutputChanged
    // Audio
    case volumeChanged, muted, unmuted
    // Network
    case internetConnected, internetLost, networkChanged
    // Input
    case keyTyped, returnKey, deleteKey, spaceKey, mouseClick, rightClick
    case capsLockOn, capsLockOff
    // Files
    case screenshotTaken, fileDownloaded, clipboardCopied, trashChanged
    // Time & activity
    case hourlyChime, halfHourChime, idleStarted, idleReturned
}

public enum TriggerCategory: String, CaseIterable, Codable, Sendable {
    case power, system, screen, apps, devices, audio, network, input, files, time

    public var title: String {
        switch self {
        case .power: "Power"
        case .system: "System"
        case .screen: "Screen & Display"
        case .apps: "Apps"
        case .devices: "Devices"
        case .audio: "Audio"
        case .network: "Network"
        case .input: "Keyboard & Mouse"
        case .files: "Files & Clipboard"
        case .time: "Time & Activity"
        }
    }
}

/// Some triggers need a macOS privacy permission before their monitor can run.
public enum PermissionKind: String, Codable, Sendable {
    case none
    case inputMonitoring
    case bluetooth
}
