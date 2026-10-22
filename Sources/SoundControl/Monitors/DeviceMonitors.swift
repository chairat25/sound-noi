import AudioToolbox
import CoreAudio
import Foundation
import IOBluetooth
import IOKit
import IOKit.usb
import SoundControlCore

/// Default output device, volume and mute via CoreAudio property listeners.
@MainActor
final class AudioDeviceMonitor: TriggerMonitor {
    let triggers: Set<TriggerID> = [.audioOutputChanged, .volumeChanged, .muted, .unmuted]
    private let sink: MonitorSink
    private var device: AudioObjectID = 0
    private var wasMuted: Bool?
    private var lastVolume: Float32?
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    private var volumeListener: AudioObjectPropertyListenerBlock?
    private var muteListener: AudioObjectPropertyListenerBlock?

    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)

    init(sink: MonitorSink) {
        self.sink = sink
    }

    func start() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.defaultDeviceChanged() }
        }
        defaultDeviceListener = listener
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddress, .main, listener)
        attach(to: Self.currentOutputDevice())
    }

    func stop() {
        detach()
        if let defaultDeviceListener {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddress, .main, defaultDeviceListener)
        }
        defaultDeviceListener = nil
    }

    /// Let the audio engine finish switching devices before playing on the new one.
    private static let outputSwitchDelay: TimeInterval = 0.25

    private var isRunning: Bool { defaultDeviceListener != nil }

    private func defaultDeviceChanged() {
        // A callback already queued on main can arrive after stop().
        guard isRunning else { return }
        let newDevice = Self.currentOutputDevice()
        guard newDevice != device else { return }
        attach(to: newDevice)
        let name = Self.name(of: newDevice)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.outputSwitchDelay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isRunning else { return }
                self.sink.emit(.audioOutputChanged, name)
            }
        }
    }

    private func attach(to newDevice: AudioObjectID) {
        detach()
        device = newDevice
        wasMuted = Self.readMute(newDevice)
        lastVolume = Self.readVolume(newDevice)
        let volume: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.volumeChanged() }
        }
        let mute: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.muteChanged() }
        }
        volumeListener = volume
        muteListener = mute
        AudioObjectAddPropertyListenerBlock(device, &Self.volumeAddress, .main, volume)
        AudioObjectAddPropertyListenerBlock(device, &Self.muteAddress, .main, mute)
    }

    private func detach() {
        guard device != 0 else { return }
        if let volumeListener { AudioObjectRemovePropertyListenerBlock(device, &Self.volumeAddress, .main, volumeListener) }
        if let muteListener { AudioObjectRemovePropertyListenerBlock(device, &Self.muteAddress, .main, muteListener) }
        volumeListener = nil
        muteListener = nil
        device = 0
    }

    private func volumeChanged() {
        guard isRunning else { return }
        let volume = Self.readVolume(device)
        defer { lastVolume = volume }
        guard let volume, volume != lastVolume else { return }
        sink.emit(.volumeChanged, "\(Int((volume * 100).rounded()))%")
    }

    private func muteChanged() {
        guard isRunning else { return }
        let muted = Self.readMute(device)
        defer { wasMuted = muted }
        guard let muted, let trigger = Edge.detect(previous: wasMuted, current: muted, rising: .muted, falling: .unmuted) else { return }
        sink.emit(trigger, nil)
    }

    private static func currentOutputDevice() -> AudioObjectID {
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultOutputAddress, 0, nil, &size, &id)
        return id
    }

    private static func readVolume(_ device: AudioObjectID) -> Float32? {
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectHasProperty(device, &volumeAddress),
              AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func readMute(_ device: AudioObjectID) -> Bool? {
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectHasProperty(device, &muteAddress),
              AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    private static func name(of device: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }
}

/// USB plug/unplug via IOKit matching notifications.
@MainActor
final class USBMonitor: TriggerMonitor {
    let triggers: Set<TriggerID> = [.usbConnected, .usbDisconnected]
    private let sink: MonitorSink
    private var port: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0

    init(sink: MonitorSink) {
        self.sink = sink
    }

    func start() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, IOServiceMatching("IOUSBHostDevice"), { context, iterator in
            guard let context else { return }
            let monitor = Unmanaged<USBMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.drain(iterator, emitting: .usbConnected) }
        }, context, &addedIterator)
        IOServiceAddMatchingNotification(port, kIOTerminatedNotification, IOServiceMatching("IOUSBHostDevice"), { context, iterator in
            guard let context else { return }
            let monitor = Unmanaged<USBMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.drain(iterator, emitting: .usbDisconnected) }
        }, context, &removedIterator)
        // Arm the notifications; devices already present are not "new".
        drain(addedIterator, emitting: nil)
        drain(removedIterator, emitting: nil)
    }

    func stop() {
        [addedIterator, removedIterator].filter { $0 != 0 }.forEach { IOObjectRelease($0) }
        addedIterator = 0
        removedIterator = 0
        if let port {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
            IONotificationPortDestroy(port)
        }
        port = nil
    }

    private func drain(_ iterator: io_iterator_t, emitting trigger: TriggerID?) {
        var names: [String] = []
        var device = IOIteratorNext(iterator)
        while device != 0 {
            var buffer = [CChar](repeating: 0, count: 128)
            if IORegistryEntryGetName(device, &buffer) == KERN_SUCCESS {
                names.append(String(cString: buffer))
            }
            IOObjectRelease(device)
            device = IOIteratorNext(iterator)
        }
        // A hub can enumerate several devices at once; one sound is enough.
        if let trigger, !names.isEmpty {
            sink.emit(trigger, names.joined(separator: ", "))
        }
    }
}

/// Bluetooth connect/disconnect. Starting this asks for Bluetooth permission once.
@MainActor
final class BluetoothMonitor: NSObject, TriggerMonitor {
    let triggers: Set<TriggerID> = [.bluetoothConnected, .bluetoothDisconnected]
    private let sink: MonitorSink
    private var connectNotification: IOBluetoothUserNotification?
    /// Disconnect registrations by device address; doubles as "currently connected".
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    /// Devices already connected when monitoring started are reported once on register; stay quiet for them.
    private var connectedAtStart: Set<String> = []

    init(sink: MonitorSink) {
        self.sink = sink
    }

    func start() {
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        connectedAtStart = Set(paired.filter { $0.isConnected() }.compactMap(\.addressString))
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
    }

    func stop() {
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotifications.values.forEach { $0.unregister() }
        disconnectNotifications = [:]
        connectedAtStart = []
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard connectNotification != nil else { return }
        let address = device.addressString ?? device.name ?? "unknown"
        guard disconnectNotifications[address] == nil else { return }
        if let disconnect = device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:))) {
            disconnectNotifications[address] = disconnect
        }
        guard connectedAtStart.remove(address) == nil else { return }
        sink.emit(.bluetoothConnected, device.name)
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        notification.unregister()
        let address = device.addressString ?? device.name ?? "unknown"
        disconnectNotifications[address] = nil
        guard connectNotification != nil else { return }
        sink.emit(.bluetoothDisconnected, device.name)
    }
}
