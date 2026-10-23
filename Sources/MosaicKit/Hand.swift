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

/// The sound of a tile going in, synthesized: no recordings. A short burst of noise for the knock
/// and a few decaying partials for the ring, mono samples in -1...1. Deterministic by variant.
nonisolated public enum Voice: Int, CaseIterable, Sendable {
    /// Glass smalti: a bright click, two high partials.
    case glass
    /// Stone (the faces): a duller, lower tock.
    case stone
    /// Gold: glass with a faint shimmer.
    case gold

    public func samples(variant: Int, rate: Double = 44_100) -> [Float] {
        let n = Int(rate * 0.14)
        var out = [Float](repeating: 0, count: n)
        var seed = UInt64(truncatingIfNeeded: variant &* 7919 &+ rawValue &* 104_729) &+ 0x2545_F491_4F6C_DD1D
        func noise() -> Float {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return Float(seed >> 40) / Float(1 << 23) - 1
        }
        let tune = 1 + 0.04 * Double(TileColor.wobble(variant, salt: 7))
        let partials: [(hz: Double, decay: Double, gain: Double)] = switch self {
        case .stone: [(620, 70, 0.25), (1310, 90, 0.12)]
        case .glass, .gold: [(2350, 45, 0.22), (5150, 70, 0.11), (7400, 95, 0.07)]
        }
        let knockDecay: Double = self == .stone ? 140 : 220, smooth: Float = self == .stone ? 0.18 : 0.6
        var low: Float = 0
        for i in 0..<n {
            let t = Double(i) / rate
            low += (noise() - low) * smooth
            var v = Double(low) * exp(-t * knockDecay) * 0.9
            for p in partials { v += sin(2 * .pi * p.hz * tune * t) * exp(-t * p.decay) * p.gain }
            if self == .gold { v += sin(2 * .pi * 3720 * tune * t) * exp(-t * 18) * 0.06 * (1 + sin(2 * .pi * 23 * t)) }
            let attack = min(1, Double(i) / 24)
            out[i] = Float(max(-1, min(1, v * attack * 0.5)))
        }
        return out
    }

    /// The voice of a tile: stone for faces, gold for gold smalti, otherwise glass.
    public static func of(_ tile: Mosaic.Tile, in mosaic: Mosaic) -> Voice {
        tile.stone ? .stone : TileColor.isGold(mosaic.palette[tile.paint]) ? .gold : .glass
    }
}
