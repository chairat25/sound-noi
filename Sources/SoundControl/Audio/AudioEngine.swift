import AVFoundation
import CoreGraphics
import OSLog

/// Low-latency, polyphonic playback: a small pool of player nodes on one engine.
///
/// Starting the engine costs ~45 ms, so while you are using the Mac (and `keepReady` is on)
/// it stays running and sounds start immediately. A running engine makes coreaudiod hold a
/// "prevent idle sleep" assertion, so once you are idle and nothing has played for a while
/// it pauses and the Mac can sleep normally.
@MainActor
final class AudioEngine {
    private static let voiceCount = 10
    private static let housekeepingInterval: TimeInterval = 5
    /// Input within this window means "the user is at the Mac".
    private static let activeUserWindow: TimeInterval = 60
    /// Grace period after the last sound before pausing an idle engine.
    private static let quietBeforePause: TimeInterval = 20

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextVoice = 0
    private var lastPlay = Date.distantPast
    private var keepReady = false
    private var housekeeping: Timer?
    private var configObserver: NSObjectProtocol?
    private let logger = Logger(subsystem: "com.pond.soundcontrol", category: "AudioEngine")

    init() {
        players = (0..<Self.voiceCount).map { _ in AVAudioPlayerNode() }
        for player in players {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: SoundLibrary.format)
        }
        engine.prepare()
        // Headphones plugged in / output switched / wake from sleep: the engine stops and must be rewired.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleConfigurationChange() }
        }
        housekeeping = Timer.scheduledTimer(withTimeInterval: Self.housekeepingInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        housekeeping?.tolerance = 1
    }

    /// Keep the output running while the user is active so the next sound has no start-up delay.
    func setKeepReady(_ isOn: Bool) {
        keepReady = isOn
        tick()
    }

    func play(_ buffer: AVAudioPCMBuffer, gain: Float) {
        guard gain > 0, startIfNeeded() else { return }
        let player = players[nextVoice]
        nextVoice = (nextVoice + 1) % players.count
        player.stop()
        player.volume = min(max(gain, 0), 1)
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
        lastPlay = Date()
    }

    func stopAll() {
        players.forEach { $0.stop() }
    }

    private func startIfNeeded() -> Bool {
        if engine.isRunning { return true }
        do {
            try engine.start()
            return true
        } catch {
            logger.error("Audio engine failed to start: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func tick() {
        let isPlayingRecently = Date().timeIntervalSince(lastPlay) < Self.quietBeforePause
        if keepReady, Self.isUserActive() {
            _ = startIfNeeded()
        } else if engine.isRunning, !isPlayingRecently {
            stopAll()
            engine.pause()
        }
    }

    private static func isUserActive() -> Bool {
        let anyInput = CGEventType(rawValue: UInt32.max)!
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput) < activeUserWindow
    }

    /// The engine has already stopped itself; rewire and resume so a sound fired right
    /// after the switch (e.g. "Audio output changed", "Mac wakes up") plays on the new device.
    private func handleConfigurationChange() {
        for player in players {
            engine.connect(player, to: engine.mainMixerNode, format: SoundLibrary.format)
        }
        engine.prepare()
        logger.info("Audio configuration changed; engine rewired")
        _ = startIfNeeded()
        lastPlay = Date()
    }
}
