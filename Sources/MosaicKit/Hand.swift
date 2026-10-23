import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// How a tile goes in, moment by moment: pressed (the tessera held over its place), settled into
/// the bed with a damped spring, and catching the light once as it does. Times in seconds from
/// when its setting began; the app draws from these, and Linux tests them.
nonisolated public enum Motion {
    /// The tessera is held raised for this long before it settles (a tap after a press skips it).
    public static let press = 0.09
    /// How long it takes to settle.
    public static let settle = 0.29
    /// When the light crosses it, and for how long.
    public static let glintStart = 0.22, glint = 0.54
    /// When it touches the bed: the sound and the tap on the finger.
    public static let contact = 0.11
    /// Everything over: the tile can be baked into the wall.
    public static let total = 0.8
    /// Tiles of one stroke settle this far apart, however fast the finger went.
    public static let rowGap = 0.045
    /// How much a raised tessera is scaled up.
    public static let lift: Float = 0.14

    /// 0 while raised, rising to 1 as it settles, overshooting by a hair.
    public static func settled(_ t: Double) -> Double {
        let x = min(max((t - press) / settle, 0), 1)
        return x >= 1 ? 1 : 1 - exp(-10 * x) * cos(9 * x)
    }

    /// How far the light has crossed the tile, 0...1, or nil when it isn't crossing.
    public static func glinting(_ t: Double) -> Double? {
        let x = (t - glintStart) / glint
        return x > 0 && x < 1 ? x : nil
    }

    /// With Reduce Motion: no rise or spring, a fade in over 150 ms.
    public static func fade(_ t: Double) -> Double { min(max(t / 0.15, 0), 1) }
}

/// The light on a tile's edges, from the upper left (as in the sketchbook's finish C).
nonisolated public enum Light {
    public static let from = SIMD2<Float>(-0.6, -0.8)

    /// How lit an edge from `a` to `b` is, -1 (facing away) to 1, given the polygon's winding.
    public static func edge(_ a: SIMD2<Float>, _ b: SIMD2<Float>, clockwise: Bool) -> Float {
        // The outward normal, in canvas units where y runs down.
        var n = SIMD2(b.y - a.y, a.x - b.x)
        if !clockwise { n = -n }
        let len = (n * n).sum().squareRoot()
        guard len > 0 else { return 0 }
        return ((n / len) * from).sum()
    }

    /// Whether corners run clockwise on screen (y down): the shoelace sum is positive.
    public static func clockwise(_ c: [SIMD2<Float>]) -> Bool {
        var s: Float = 0
        for i in c.indices { let a = c[i], b = c[(i + 1) % c.count]; s += a.x * b.y - b.x * a.y }
        return s > 0
    }

    /// The corner the light reaches first: where glass glints.
    public static func litCorner(_ c: [SIMD2<Float>]) -> Int {
        c.indices.min { (c[$0] * from).sum() > (c[$1] * from).sum() } ?? 0
    }
}

/// The tune setting plays: Paint by Moonlight's painting melody, one note per tile set whatever
/// its paint, so any order of setting sounds like the same tune. Copied, with its scales, from
/// pbordjadze/paint-by-number at 805b7ff (`App/PaintByNumber/Feedback/PaintingMelody.swift` and
/// `SoundPlayer.swift`), as Paul asked: "the same melodies as the original app but in a clink of
/// mosaic tiles being placed".
nonisolated public struct Melody: Sendable {
    /// Indices into a scale: six eight-note phrases that rise, answer and settle on the first note.
    public static let tune: [Int] = [
        2, 3, 4, 3, 2, 1, 0, 1,
        2, 3, 4, 5, 4, 3, 2, 3,
        4, 5, 6, 7, 6, 5, 4, 5,
        6, 7, 8, 7, 6, 5, 4, 3,
        2, 3, 4, 3, 2, 1, 2, 3,
        5, 4, 3, 2, 1, 2, 1, 0,
    ]
    public static let phraseLength = 8
    /// After a pause this long the tune picks up at the start of its next phrase.
    public static let breath: TimeInterval = 5

    /// Which scale the tune is in (an option until Paul narrows it).
    public enum Mode: String, CaseIterable, Sendable {
        /// D major pentatonic over two octaves from D4 (Paint by Moonlight's Sun).
        case major
        /// The same five notes as their minor, from the B below (its Moon).
        case minor

        public var scale: [Double] {
            let major = [293.66, 329.63, 369.99, 440.00, 493.88, 587.33, 659.26, 739.99, 880.00, 987.77, 1174.66, 1318.51]
            return self == .major ? major : [246.94] + major.dropLast()
        }
    }

    public private(set) var position = 0
    /// The most recently played note (the tune's first before any).
    public private(set) var latest = Self.tune[0]
    private var lastPlayed: Date?

    public init() {}

    /// The next note's place on the scale for a tile set at `now`, and whether it ends its phrase.
    public mutating func next(at now: Date) -> (index: Int, endsPhrase: Bool) {
        if let lastPlayed, now.timeIntervalSince(lastPlayed) >= Self.breath, !position.isMultiple(of: Self.phraseLength) {
            position = (position / Self.phraseLength + 1) * Self.phraseLength % Self.tune.count
        }
        lastPlayed = now
        latest = Self.tune[position]
        let ends = (position + 1).isMultiple(of: Self.phraseLength)
        position = (position + 1) % Self.tune.count
        return (latest, ends)
    }
}

/// The sound of a tile going in, synthesized: no recordings. A clink, a note of the tune: a short
/// tap of noise as the tessera meets the bed, then the pitched ring of what it is made of. Mono
/// samples in -1...1, deterministic.
nonisolated public enum Voice: Int, CaseIterable, Sendable {
    /// Glass smalti: a bright clink, ringing like a struck bar (its overtones off the octave).
    case glass
    /// Stone (the faces): a drier clack, the note short and the tap louder.
    case stone
    /// Gold: glass with a faint shimmer, its gold leaf under a glass skin.
    case gold

    /// The clink at `frequency` Hz.
    public func clink(frequency f: Double, rate: Double = 44_100) -> [Float] {
        let length = self == .stone ? 0.28 : 0.6, fade = 0.04
        let n = Int(rate * length)
        var out = [Float](repeating: 0, count: n)
        var seed = UInt64(f * 1000) &+ UInt64(rawValue) &* 0x9E37_79B9 &+ 0x2545_F491_4F6C_DD1D
        func noise() -> Double {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return Double(seed >> 11) / Double(1 << 53) * 2 - 1
        }
        // A free bar's modes (1, 2.76, 5.40): glass rings on, stone damps them fast.
        let partials: [(ratio: Double, decay: Double, gain: Double)] = switch self {
        case .stone: [(1, 26, 0.75), (2.76, 60, 0.22), (5.40, 110, 0.08)]
        case .glass, .gold: [(1, 7.5, 0.7), (2.76, 16, 0.3), (5.40, 34, 0.14)]
        }
        let tap: (gain: Double, decay: Double, smooth: Double) = self == .stone ? (0.55, 260, 0.3) : (0.35, 700, 0.85)
        var low = 0.0, previous = 0.0
        for i in 0..<n {
            let t = Double(i) / rate
            // The tap: noise, darker for stone, the brighter difference of it for glass.
            low += (noise() - low) * tap.smooth
            let click = self == .stone ? low : low - previous
            previous = low
            var v = click * tap.gain * exp(-t * tap.decay)
            let attack = min(1, t / 0.0015)
            for p in partials { v += attack * sin(2 * .pi * f * p.ratio * t) * exp(-t * p.decay) * p.gain }
            if self == .gold { v += attack * 0.1 * sin(2 * .pi * (2 * f + 4) * t) * exp(-t * 5) }
            let tail = min(1, (length - t) / fade)
            out[i] = Float(max(-1, min(1, v * tail * 0.55)))
        }
        return out
    }

    /// The voice of a tile: stone for faces, gold for gold smalti, otherwise glass.
    public static func of(_ tile: Mosaic.Tile, in mosaic: Mosaic) -> Voice {
        tile.stone ? .stone : TileColor.isGold(mosaic.palette[tile.paint]) ? .gold : .glass
    }
}
