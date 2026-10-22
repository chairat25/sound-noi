import AppKit
import CoreGraphics
import SoundControlCore

/// Keyboard and mouse sounds through a listen-only event tap.
/// Needs Input Monitoring; only key *codes* are inspected, never what is typed.
@MainActor
final class InputMonitor: TriggerMonitor {
    static let permissionMessage = "Needs Input Monitoring permission"

    let triggers: Set<TriggerID> = [
        .keyTyped, .returnKey, .deleteKey, .spaceKey, .mouseClick, .rightClick, .capsLockOn, .capsLockOff
    ]
    private enum KeyCode {
        static let returnKeys: Set<Int64> = [36, 76]
        static let deleteKeys: Set<Int64> = [51, 117]
        static let space: Int64 = 49
        static let capsLock: Int64 = 57
    }

    private let sink: MonitorSink
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var capsLockOn: Bool?

    init(sink: MonitorSink) {
        self.sink = sink
    }

    static var hasPermission: Bool { CGPreflightListenEventAccess() }

    @discardableResult
    static func requestPermission() -> Bool { CGRequestListenEventAccess() }

    func start() {
        guard Self.hasPermission else {
            Self.requestPermission()
            sink.setUnavailable(triggers, Self.permissionMessage)
            return
        }
        let events: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .flagsChanged]
        let mask = events.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                          eventsOfInterest: mask, callback: { _, type, event, context in
            if let context {
                let monitor = Unmanaged<InputMonitor>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { monitor.handle(type, event) }
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: context) else {
            sink.setUnavailable(triggers, Self.permissionMessage)
            return
        }
        sink.setUnavailable(triggers, nil)
        capsLockOn = NSEvent.modifierFlags.contains(.capsLock)
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        tap = nil
        source = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .keyDown:
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return }
            sink.emit(keyTrigger(for: event.getIntegerValueField(.keyboardEventKeycode)), nil)
        case .leftMouseDown:
            sink.emit(.mouseClick, nil)
        case .rightMouseDown:
            sink.emit(.rightClick, nil)
        case .flagsChanged:
            guard event.getIntegerValueField(.keyboardEventKeycode) == KeyCode.capsLock else { return }
            let isOn = event.flags.contains(.maskAlphaShift)
            if let trigger = Edge.detect(previous: capsLockOn, current: isOn, rising: .capsLockOn, falling: .capsLockOff) {
                sink.emit(trigger, nil)
            }
            capsLockOn = isOn
        default:
            break
        }
    }

    /// Special keys get their own sound when that trigger is on; otherwise they sound like any key.
    private func keyTrigger(for code: Int64) -> TriggerID {
        let specific: TriggerID? = if KeyCode.returnKeys.contains(code) {
            .returnKey
        } else if KeyCode.deleteKeys.contains(code) {
            .deleteKey
        } else if code == KeyCode.space {
            .spaceKey
        } else {
            nil
        }
        guard let specific, sink.isEnabled(specific) else { return .keyTyped }
        return specific
    }
}
