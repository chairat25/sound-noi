import Foundation

/// A single note inside a motif. `semitone` is relative to the timbre's base pitch.
public struct Note: Sendable, Equatable {
    public let semitone: Double
    public let start: Double
    public let duration: Double
    public let velocity: Double
    public let isNoise: Bool

    public init(_ semitone: Double, at start: Double, for duration: Double, velocity: Double = 1, isNoise: Bool = false) {
        self.semitone = semitone
        self.start = start
        self.duration = duration
        self.velocity = velocity
        self.isNoise = isNoise
    }
}

/// The musical "gesture" of a sound, independent of instrument. Each pack renders
/// every motif with its own timbre, so a trigger keeps its meaning across packs.
public enum Motif: String, CaseIterable, Codable, Sendable {
    case rise, fall, success, warning, alarm, ascend, descend, chime, toll
    case tick, click, tap, pop, thud, doubleUp, doubleDown, sparkle, whoosh

    public var title: String {
        switch self {
        case .rise: "Rise"
        case .fall: "Fall"
        case .success: "Success"
        case .warning: "Warning"
        case .alarm: "Alarm"
        case .ascend: "Ascend"
        case .descend: "Descend"
        case .chime: "Chime"
        case .toll: "Toll"
        case .tick: "Tick"
        case .click: "Click"
        case .tap: "Tap"
        case .pop: "Pop"
        case .thud: "Thud"
        case .doubleUp: "Double up"
        case .doubleDown: "Double down"
        case .sparkle: "Sparkle"
        case .whoosh: "Whoosh"
        }
    }

    /// Notes for a given take. Take 0 is the canonical version; later takes are
    /// transposed and slightly re-timed so rotating between them feels alive.
    public func notes(take: Int) -> [Note] {
        let transpose = Motif.takeTranspose[abs(take) % Motif.takeTranspose.count]
        let tempo = Motif.takeTempo[abs(take) % Motif.takeTempo.count]
        return baseNotes.map {
            Note($0.semitone + transpose, at: $0.start * tempo, for: $0.duration * tempo,
                 velocity: $0.velocity, isNoise: $0.isNoise)
        }
    }

    public static let takeCount = 2
    private static let takeTranspose: [Double] = [0, 2]
    private static let takeTempo: [Double] = [1, 0.88]

    private var baseNotes: [Note] {
        switch self {
        case .rise: Motif.run([0, 4, 7, 12], step: 0.07, length: 0.35)
        case .fall: Motif.run([12, 7, 4, 0], step: 0.07, length: 0.35)
        case .success: Motif.run([0, 4, 7], step: 0.08, length: 0.25) + [Note(12, at: 0.24, for: 0.7)]
        case .warning: [Note(5, at: 0, for: 0.22, velocity: 0.85), Note(0, at: 0.2, for: 0.4, velocity: 0.85)]
        case .alarm: Motif.run([12, 7, 12, 7], step: 0.12, length: 0.14)
        case .ascend: Motif.run([0, 2, 4, 7, 9, 12], step: 0.09, length: 0.5, velocity: 0.8)
        case .descend: Motif.run([12, 9, 7, 4, 2, 0], step: 0.1, length: 0.5, velocity: 0.8)
        case .chime: [Note(0, at: 0, for: 1.2), Note(7, at: 0, for: 1.2, velocity: 0.45)]
        case .toll: [Note(0, at: 0, for: 1.4), Note(7, at: 0.45, for: 1.2, velocity: 0.7), Note(12, at: 0.9, for: 1.4, velocity: 0.6)]
        case .tick: [Note(12, at: 0, for: 0.04, velocity: 0.6)]
        case .click: [Note(19, at: 0, for: 0.025, velocity: 0.5), Note(0, at: 0, for: 0.015, velocity: 0.25, isNoise: true)]
        case .tap: [Note(0, at: 0, for: 0.07, velocity: 0.55)]
        case .pop: [Note(7, at: 0, for: 0.09, velocity: 0.8)]
        case .thud: [Note(-12, at: 0, for: 0.28, velocity: 0.95)]
        case .doubleUp: [Note(0, at: 0, for: 0.18), Note(7, at: 0.1, for: 0.3)]
        case .doubleDown: [Note(7, at: 0, for: 0.18), Note(0, at: 0.1, for: 0.3)]
        case .sparkle: Motif.run([12, 16, 19, 24], step: 0.045, length: 0.3, velocity: 0.6)
        case .whoosh: [Note(0, at: 0, for: 0.45, velocity: 0.7, isNoise: true)]
        }
    }

    private static func run(_ semitones: [Double], step: Double, length: Double, velocity: Double = 1) -> [Note] {
        semitones.enumerated().map { index, semitone in
            Note(semitone, at: Double(index) * step, for: length, velocity: velocity)
        }
    }
}
