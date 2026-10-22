import Foundation

public enum Waveform: String, Codable, Sendable {
    case sine, square, triangle
}

/// One sine component of an additive voice.
public struct Partial: Sendable, Equatable {
    public let ratio: Double
    public let amplitude: Double

    public init(_ ratio: Double, _ amplitude: Double) {
        self.ratio = ratio
        self.amplitude = amplitude
    }
}

/// The "instrument" of a synth pack: how each note of a motif is voiced.
public struct Timbre: Sendable, Equatable {
    /// Frequency ratio + relative amplitude for each partial (additive synthesis).
    public let partials: [Partial]
    public let waveform: Waveform
    public let baseFrequency: Double
    /// Attack time in seconds.
    public let attack: Double
    /// Exponential decay time constant in seconds (smaller = shorter, plucky).
    public let decay: Double
    public let vibratoDepth: Double
    public let vibratoRate: Double
    /// How much of a soft noise transient is mixed into tonal notes (0...1).
    public let transient: Double
    public let gain: Double

    public init(partials: [Partial], waveform: Waveform = .sine, baseFrequency: Double,
                attack: Double, decay: Double, vibratoDepth: Double = 0, vibratoRate: Double = 0,
                transient: Double = 0, gain: Double = 0.8) {
        self.partials = partials
        self.waveform = waveform
        self.baseFrequency = baseFrequency
        self.attack = attack
        self.decay = decay
        self.vibratoDepth = vibratoDepth
        self.vibratoRate = vibratoRate
        self.transient = transient
        self.gain = gain
    }
}

/// Renders motifs into mono PCM samples. Pure and deterministic (seeded noise),
/// so the same pack/motif/take always produces the same sound.
public enum Synth {
    public static let defaultSampleRate: Double = 44_100
    /// Silence appended after the last note so release tails are not clipped.
    static let tailSeconds: Double = 0.25
    static let peakTarget: Float = 0.89

    public static func render(_ motif: Motif, take: Int, timbre: Timbre, sampleRate: Double = defaultSampleRate) -> [Float] {
        let notes = motif.notes(take: take)
        let end = notes.map { $0.start + $0.duration }.max() ?? 0
        let frameCount = Int((end + tailSeconds) * sampleRate)
        guard frameCount > 0 else { return [] }

        var mix = [Float](repeating: 0, count: frameCount)
        var noise = NoiseGenerator(seed: UInt64(abs(take) + 1) &* 0x9E37_79B9_7F4A_7C15)
        for note in notes {
            let voice = note.isNoise
                ? renderNoise(note, timbre: timbre, sampleRate: sampleRate, noise: &noise)
                : renderTone(note, timbre: timbre, sampleRate: sampleRate, noise: &noise)
            let offset = Int(note.start * sampleRate)
            for (index, sample) in voice.enumerated() where offset + index < frameCount {
                mix[offset + index] += sample
            }
        }
        return normalized(mix)
    }

    public static func frequency(semitone: Double, base: Double) -> Double {
        base * pow(2, semitone / 12)
    }

    static func normalized(_ samples: [Float]) -> [Float] {
        let peak = samples.map(abs).max() ?? 0
        guard peak > 0 else { return samples }
        let scale = peakTarget / peak
        return samples.map { $0 * scale }
    }

    private static func renderTone(_ note: Note, timbre: Timbre, sampleRate: Double, noise: inout NoiseGenerator) -> [Float] {
        let frequency = frequency(semitone: note.semitone, base: timbre.baseFrequency)
        // Let the exponential decay ring past the nominal duration, then fade out.
        let ringLength = note.duration + min(timbre.decay * 2, 1.0)
        let count = Int(ringLength * sampleRate)
        let releaseStart = note.duration
        let amplitudeSum = timbre.partials.map(\.amplitude).reduce(0, +)
        let partialScale = amplitudeSum > 0 ? 1 / amplitudeSum : 1

        return (0..<count).map { index in
            let t = Double(index) / sampleRate
            let vibrato = timbre.vibratoDepth * sin(2 * .pi * timbre.vibratoRate * t)
            var value = 0.0
            for partial in timbre.partials {
                let phase = 2 * .pi * frequency * partial.ratio * (t + vibrato / max(frequency, 1))
                value += partial.amplitude * oscillate(timbre.waveform, phase: phase)
            }
            value *= partialScale
            if timbre.transient > 0, t < 0.012 {
                value += timbre.transient * noise.next() * (1 - t / 0.012)
            }
            let envelope = envelopeValue(t: t, attack: timbre.attack, decay: timbre.decay,
                                         releaseStart: releaseStart, end: ringLength)
            return Float(value * envelope * note.velocity * timbre.gain)
        }
    }

    private static func renderNoise(_ note: Note, timbre: Timbre, sampleRate: Double, noise: inout NoiseGenerator) -> [Float] {
        let count = Int(note.duration * sampleRate)
        var low = 0.0
        return (0..<count).map { index in
            let t = Double(index) / sampleRate
            // One-pole low-pass whose cutoff sweeps up then down: a soft "whoosh".
            let progress = t / max(note.duration, 0.001)
            let sweep = 0.05 + 0.4 * sin(.pi * progress)
            low += sweep * (noise.next() - low)
            let envelope = sin(.pi * progress)
            return Float(low * envelope * note.velocity * timbre.gain * 2)
        }
    }

    static func oscillate(_ waveform: Waveform, phase: Double) -> Double {
        switch waveform {
        case .sine:
            return sin(phase)
        case .square:
            return sin(phase) >= 0 ? 0.6 : -0.6
        case .triangle:
            let normalized = phase / (2 * .pi)
            return 4 * abs(normalized - floor(normalized + 0.5)) - 1
        }
    }

    static func envelopeValue(t: Double, attack: Double, decay: Double, releaseStart: Double, end: Double) -> Double {
        let attackGain = attack > 0 ? min(t / attack, 1) : 1
        let decayGain = exp(-max(t - attack, 0) / max(decay, 0.001))
        let releaseLength = max(end - releaseStart, 0.001)
        let releaseGain = t <= releaseStart ? 1 : max(0, 1 - (t - releaseStart) / releaseLength)
        return attackGain * decayGain * releaseGain
    }
}

/// Small deterministic xorshift noise source in -1...1.
struct NoiseGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xDEAD_BEEF : seed
    }

    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state % 2_000_001) / 1_000_000 - 1
    }
}
