import AppKit
import Observation
import OSLog
import SoundControlCore

/// The app's single source of truth: owns the config, reacts to monitor events,
/// and plays sounds. Views read it and call its intent methods.
@MainActor
@Observable
final class AppModel {
    private static let saveDelay: TimeInterval = 0.4
    private static let startupSoundDelay: TimeInterval = 1.5

    private(set) var config: AppConfig
    private(set) var log = ActivityLog()
    /// Triggers that cannot work right now, with the reason shown in the UI.
    private(set) var unavailable: [TriggerID: String] = [:]
    /// Last user-facing problem (save failure, import error…), shown as a banner.
    var alertMessage: String?
    private(set) var isLaunchAtLoginEnabled = LoginItem.isEnabled
    private(set) var hasInputPermission = InputMonitor.hasPermission

    @ObservationIgnored private let store: ConfigStore
    @ObservationIgnored private let soundStore: UserSoundStore
    @ObservationIgnored private let library: SoundLibrary
    @ObservationIgnored private let engine = AudioEngine()
    @ObservationIgnored private var hub: MonitorHub?
    @ObservationIgnored private var lastPlayed: [TriggerID: Date] = [:]
    @ObservationIgnored private var lastIndex: [TriggerID: Int] = [:]
    /// Start of the last non-chatty sound, for burst suppression.
    @ObservationIgnored private var lastEventSound: Date?
    @ObservationIgnored private var pendingWarm: DispatchWorkItem?
    /// `kill`/`pkill` should still go through normal termination so macOS sounds are restored.
    @ObservationIgnored private var termSignal: DispatchSourceSignal?
    @ObservationIgnored private var pendingSave: DispatchWorkItem?
    @ObservationIgnored private let logger = Logger(subsystem: "com.pond.soundcontrol", category: "AppModel")

    init() {
        let folder = ConfigStore.applicationSupport()
        store = ConfigStore(fileURL: folder.appendingPathComponent("config.json"))
        soundStore = UserSoundStore(folder: folder.appendingPathComponent("Sounds", isDirectory: true))
        library = SoundLibrary(userSoundsFolder: soundStore.folder)

        let loaded = store.load()
        config = loaded.config
        if let backup = loaded.recoveredFrom {
            alertMessage = "Settings were unreadable and were reset. The old file was kept at \(backup.path)."
        }

        let sink = MonitorSink(
            emit: { [weak self] trigger, context in self?.handle(trigger, context: context) },
            setUnavailable: { [weak self] triggers, reason in self?.markUnavailable(triggers, reason: reason) },
            isEnabled: { [weak self] trigger in self?.config.isEnabled(trigger) ?? false }
        )
        hub = MonitorHub(sink: sink, settings: { [weak self] in self?.config ?? .default })
        // The model is created before NSApplication finishes launching; start monitors on the next run-loop turn.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.installTerminationSignal()
                self.config = self.reconcileTweaks(self.config)
                self.hub?.reconcile(enabled: self.config.enabledTriggers, isListening: self.config.isListening)
                self.applyAudioReadiness()
                self.warmSoundCache()
            }
        }

        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Hand macOS its own sounds back while we are not running to replace them.
                self.config = self.reconcileTweaks(self.config, appIsRunning: false)
                self.flushSave()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.startupSoundDelay) { [weak self] in
            MainActor.assumeIsolated { self?.handle(.appStarted, context: nil) }
        }
    }

    // MARK: - Events

    func handle(_ trigger: TriggerID, context: String?) {
        let now = Date()
        let decision = PlaybackGate.decide(trigger, config: config, now: now, lastPlayed: lastPlayed[trigger],
                                           lastEventSound: lastEventSound)
        let info = TriggerCatalog.info(for: trigger)
        switch decision {
        case let .skipped(reason):
            if reason.isWorthLogging, !info.isChatty {
                record(trigger, now, skip: reason, sound: nil, context: context)
            }
        case .play:
            let played = playNext(for: trigger)
            lastPlayed[trigger] = now
            if !info.isChatty, played != nil { lastEventSound = now }
            if !info.isChatty {
                record(trigger, now, skip: played == nil ? .noSound : nil, sound: played, context: context)
            }
        }
    }

    /// Plays the next candidate for a trigger and returns its display name.
    @discardableResult
    private func playNext(for trigger: TriggerID) -> String? {
        let candidates = SoundResolver.candidates(for: trigger, in: config)
        let setting = config.setting(for: trigger)
        guard let first = SoundResolver.nextIndex(count: candidates.count, last: lastIndex[trigger], mode: setting.playback) else {
            return nil
        }
        // If the chosen file cannot be loaded, fall through to the following candidates.
        for offset in 0..<candidates.count {
            let index = (first + offset) % candidates.count
            let ref = candidates[index]
            if play(ref, gain: PlaybackGate.gain(for: trigger, config: config)) {
                lastIndex[trigger] = index
                return SoundResolver.displayName(of: ref, in: config)
            }
        }
        return nil
    }

    @discardableResult
    private func play(_ ref: SoundRef, gain: Float) -> Bool {
        guard let buffer = library.buffer(for: ref, userSounds: config.userSounds) else {
            logger.error("No buffer for \(ref.string, privacy: .public)")
            return false
        }
        engine.play(buffer, gain: gain)
        return true
    }

    private func record(_ trigger: TriggerID, _ date: Date, skip: SkipReason?, sound: String?, context: String?) {
        log = log.appending(ActivityEntry(trigger: trigger, date: date, skipReason: skip, soundName: sound, context: context))
    }

    private func markUnavailable(_ triggers: Set<TriggerID>, reason: String?) {
        var next = unavailable
        for trigger in triggers { next[trigger] = reason }
        unavailable = next
        hasInputPermission = InputMonitor.hasPermission
    }

    // MARK: - Preview (ignores listening, quiet hours and cooldowns)

    func preview(_ trigger: TriggerID) {
        engine.stopAll()
        playNext(for: trigger)
    }

    func preview(_ ref: SoundRef, volume: Double = 1) {
        engine.stopAll()
        play(ref, gain: Float(config.masterVolume * volume))
    }

    // MARK: - Config changes

    func update(_ transform: (AppConfig) -> AppConfig) {
        let next = reconcileTweaks(transform(config))
        guard next != config else { return }
        config = next
        hub?.reconcile(enabled: config.enabledTriggers, isListening: config.isListening)
        applyAudioReadiness()
        scheduleSave()
        scheduleWarm()
    }

    func setTrigger(_ trigger: TriggerID, enabled: Bool) {
        if enabled, TriggerCatalog.info(for: trigger).permission == .inputMonitoring, !InputMonitor.hasPermission {
            InputMonitor.requestPermission()
        }
        update { $0.updatingTrigger(trigger) { $0.enabled(enabled) } }
        lastIndex[trigger] = nil
    }

    func setSounds(_ sounds: [SoundRef], for trigger: TriggerID) {
        update { $0.updatingTrigger(trigger) { $0.withSounds(sounds) } }
        lastIndex[trigger] = nil
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
        } catch {
            alertMessage = "Could not change Launch at Login: \(error.localizedDescription). Run the app from SoundControl.app."
        }
        isLaunchAtLoginEnabled = LoginItem.isEnabled
    }

    /// Call after the user grants Input Monitoring in System Settings.
    func recheckInputPermission() {
        hasInputPermission = InputMonitor.hasPermission
        hub?.restart(monitorFor: .keyTyped)
    }

    /// Routes SIGTERM (`kill`, `pkill`, logout of a stuck app) through normal termination so
    /// macOS sounds are restored. Installed after launch: AppKit resets the disposition while starting up.
    private func installTerminationSignal() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        termSignal = source
    }

    // MARK: - Latency

    private func applyAudioReadiness() {
        engine.setKeepReady(config.keepAudioReady && config.isListening)
    }

    /// Loads every sound an enabled trigger could play, so the first play never waits on disk or synthesis.
    private func warmSoundCache() {
        for trigger in config.enabledTriggers {
            for ref in SoundResolver.candidates(for: trigger, in: config) {
                _ = library.buffer(for: ref, userSounds: config.userSounds)
            }
        }
    }

    private func scheduleWarm() {
        pendingWarm?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.warmSoundCache() }
        }
        pendingWarm = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDelay, execute: work)
    }

    // MARK: - macOS sounds that overlap ours

    /// Brings macOS preferences in line with `desiredTweaks` and returns the config recording
    /// what was applied. Originals are saved right away: they are the only way back.
    private func reconcileTweaks(_ config: AppConfig, appIsRunning: Bool = true) -> AppConfig {
        let desired = config.desiredTweaks(appIsRunning: appIsRunning)
        let next = MacSoundTweak.allCases.reduce(config) { config, tweak in
            if desired.contains(tweak), !config.isApplied(tweak) {
                guard let originals = MacPreferences.apply(tweak) else {
                    alertMessage = "macOS did not accept the change to “\(tweak.title)”."
                    return config
                }
                return config.applyingTweak(tweak, originals: originals)
            }
            if !desired.contains(tweak), let originals = config.appliedTweaks[tweak] {
                MacPreferences.revert(tweak, originals: originals)
                return config.revertingTweak(tweak)
            }
            return config
        }
        if next.appliedTweaks != config.appliedTweaks {
            save(next)
        }
        return next
    }

    func resetAll() {
        update { $0.reset() }
        lastIndex = [:]
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let snapshot = config
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.save(snapshot) }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDelay, execute: work)
    }

    private func save(_ snapshot: AppConfig) {
        do {
            try store.save(snapshot)
        } catch {
            logger.error("Save failed: \(error.localizedDescription, privacy: .public)")
            alertMessage = error.localizedDescription
        }
    }

    func flushSave() {
        pendingSave?.cancel()
        save(config)
    }

    // MARK: - My Sounds

    /// Imports files and returns the new sounds; problems are reported in `alertMessage`.
    @discardableResult
    func importSounds(_ urls: [URL]) -> [UserSound] {
        var imported: [UserSound] = []
        var problems: [String] = []
        for url in urls {
            let isScoped = url.startAccessingSecurityScopedResource()
            defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
            do {
                imported.append(try soundStore.importFile(at: url))
            } catch {
                problems.append(error.localizedDescription)
            }
        }
        update { config in imported.reduce(config) { $0.addingUserSound($1) } }
        if !problems.isEmpty {
            alertMessage = problems.joined(separator: "\n")
        }
        return imported
    }

    func renameSound(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update { $0.renamingUserSound(id, to: String(trimmed.prefix(60))) }
    }

    func deleteSound(_ id: UUID) {
        guard let sound = config.userSound(id: id) else { return }
        soundStore.delete(sound)
        library.forget(.user(id: id))
        update { $0.removingUserSound(id) }
    }

    func revealSoundsFolder() {
        try? FileManager.default.createDirectory(at: soundStore.folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(soundStore.folder)
    }

    // MARK: - Custom packs

    @discardableResult
    func createPack(from base: BuiltInPack, name: String? = nil) -> CustomPack {
        let pack = CustomPack(name: name ?? "My \(base.title) Pack", base: base)
        update { $0.addingCustomPack(pack).selectingPack(.custom(pack.id)) }
        return pack
    }

    func updatePack(_ id: UUID, _ transform: (CustomPack) -> CustomPack) {
        update { $0.updatingCustomPack(id, transform) }
    }

    func deletePack(_ id: UUID) {
        update { $0.removingCustomPack(id) }
    }

    func exportPack(_ pack: CustomPack, to url: URL) {
        do {
            try PackPorter(soundStore: soundStore).export(pack, library: config.userSounds, to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func importPack(from url: URL) {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let result = try PackPorter(soundStore: soundStore).importPack(from: url)
            update { config in
                result.sounds.reduce(config) { $0.addingUserSound($1) }
                    .addingCustomPack(result.pack)
                    .selectingPack(.custom(result.pack.id))
            }
            if !result.skipped.isEmpty {
                alertMessage = "Imported “\(result.pack.name)”, but some sounds were skipped:\n" + result.skipped.joined(separator: "\n")
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}
