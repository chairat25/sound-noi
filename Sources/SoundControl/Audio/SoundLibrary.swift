@preconcurrency import AVFoundation
import OSLog
import SoundControlCore

/// Turns a `SoundRef` into a ready-to-play buffer in one shared format, caching the result.
@MainActor
final class SoundLibrary {
    static let format = AVAudioFormat(standardFormatWithSampleRate: Synth.defaultSampleRate, channels: 2)!
    static let systemSoundsFolder = URL(fileURLWithPath: "/System/Library/Sounds", isDirectory: true)

    private let userSoundsFolder: URL
    private var cache: [SoundRef: AVAudioPCMBuffer] = [:]
    private let logger = Logger(subsystem: "com.pond.soundcontrol", category: "SoundLibrary")

    init(userSoundsFolder: URL) {
        self.userSoundsFolder = userSoundsFolder
    }

    func buffer(for ref: SoundRef, userSounds: [UserSound]) -> AVAudioPCMBuffer? {
        if let cached = cache[ref] { return cached }
        let buffer: AVAudioPCMBuffer?
        switch ref {
        case let .synth(pack, motif, take):
            buffer = pack.timbre.flatMap { Self.makeBuffer(samples: Synth.render(motif, take: take, timbre: $0)) }
        case let .system(name):
            buffer = loadFile(Self.systemSoundsFolder.appendingPathComponent("\(name).aiff"))
        case let .user(id):
            buffer = userSounds.first { $0.id == id }
                .flatMap { loadFile(userSoundsFolder.appendingPathComponent($0.fileName)) }
        }
        if let buffer { cache[ref] = buffer }
        return buffer
    }

    func forget(_ ref: SoundRef) {
        cache[ref] = nil
    }

    nonisolated static func duration(of url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0 else { return nil }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    private static func makeBuffer(samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            for channel in 0..<Int(format.channelCount) {
                channels[channel].update(from: source.baseAddress!, count: samples.count)
            }
        }
        return buffer
    }

    /// Reads any supported file and converts it to the shared playback format.
    private func loadFile(_ url: URL) -> AVAudioPCMBuffer? {
        do {
            let file = try AVAudioFile(forReading: url)
            guard let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
            try file.read(into: source)
            return try convert(source)
        } catch {
            logger.error("Failed to load sound at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func convert(_ source: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer? {
        if source.format == Self.format { return source }
        guard let converter = AVAudioConverter(from: source.format, to: Self.format) else { return nil }
        let ratio = Self.format.sampleRate / source.format.sampleRate
        let capacity = AVAudioFrameCount(Double(source.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: capacity) else { return nil }

        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .endOfStream
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return source
        }
        if let conversionError { throw conversionError }
        return status == .error ? nil : output
    }
}
