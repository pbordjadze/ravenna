#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// How set tiles are drawn: the same mosaic and numbers, three looks (sketchbook round 2). An
/// option for the painter until Paul narrows it (issues #6, #12).
nonisolated public enum Finish: String, CaseIterable, Sendable, Codable {
    /// Flat tiles in their paint on light grout of one colour, a thin dark edge: the prototype's look.
    case flat
    /// Flat tiles on the painted bed: the joints take the colour of the tiles round them, as the
    /// beds under Byzantine tesserae were painted.
    case bed
    /// The painted bed, and tiles with material: each a little different in tone, a lit edge,
    /// glass outside the face and matte stone in it, gold catching the light at its own angle.
    case material

    public var name: String {
        switch self {
        case .flat: "Flat, light grout"
        case .bed: "Painted bed"
        case .material: "Glass and stone"
        }
    }

    /// Whether the ground under the tiles is the painted bed (otherwise light grout).
    public var paintedBed: Bool { self != .flat }
}

/// The detail option (issue #11): how many pieces the same picture is laid in.
nonisolated public enum Detail: String, CaseIterable, Sendable, Codable {
    case fewer, standard, more

    public var name: String {
        switch self {
        case .fewer: "Fewer pieces"
        case .standard: "Standard"
        case .more: "More pieces"
        }
    }
}

/// The colours a tile is drawn in.
nonisolated public enum TileColor {
    /// A deterministic number in -1...1 for a tile: its batch's difference, its gold's tilt.
    public static func wobble(_ tile: Int, salt: UInt64 = 0) -> Float {
        var z = UInt64(truncatingIfNeeded: tile) &+ 0x9E37_79B9_7F4A_7C15 &* (salt &+ 1)
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Float(z >> 40) / Float(1 << 23) - 1
    }

    /// Gold smalti: light, saturated and yellow (OKLab lightness over 0.55, chroma over 0.07, hue
    /// between 55° and 105°), as `sketchbook/render.py` finds it.
    public static func isGold(_ rgb: SIMD3<Float>) -> Bool {
        let lab = OKLab.from(rgb)
        let chroma = (lab.y * lab.y + lab.z * lab.z).squareRoot()
        let hue = atan2Degrees(lab.z, lab.y)
        return lab.x > 0.55 && chroma > 0.07 && hue > 55 && hue < 105
    }

    /// A set tile's body colour in a finish: its paint, in `material` nudged in tone by its batch
    /// and, for gold, brightened or dimmed by its tilt.
    public static func body(_ paint: SIMD3<Float>, tile: Int, finish: Finish) -> SIMD3<Float> {
        guard finish == .material else { return paint }
        var lab = OKLab.from(paint)
        lab.x += 0.012 * wobble(tile)
        lab.y += 0.004 * wobble(tile, salt: 1)
        lab.z += 0.004 * wobble(tile, salt: 2)
        var rgb = OKLab.toRGB(lab)
        if isGold(paint) { rgb *= 1 + 0.2 * wobble(tile, salt: 3) }
        return clamp(rgb)
    }

    /// The lit and shaded sides of a tile in `material`: glass catches more light at its edge than
    /// stone does.
    public static func bevel(_ body: SIMD3<Float>, stone: Bool) -> (lit: SIMD3<Float>, shade: SIMD3<Float>) {
        let k: Float = stone ? 0.10 : 0.22
        return (clamp(body * (1 + k) + k * 0.25), clamp(body * (1 - k * 0.9)))
    }

    static func clamp(_ v: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(min(max(v.x, 0), 1), min(max(v.y, 0), 1), min(max(v.z, 0), 1))
    }
}

/// Björn Ottosson's OKLab (2020), from and to gamma-encoded sRGB.
nonisolated public enum OKLab {
    static func linear(_ c: Float) -> Float { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    static func encoded(_ c: Float) -> Float { c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055 }

    public static func from(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        let r = linear(rgb.x), g = linear(rgb.y), b = linear(rgb.z)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return SIMD3(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                     1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                     0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    public static func toRGB(_ lab: SIMD3<Float>) -> SIMD3<Float> {
        let l = pow3(lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z)
        let m = pow3(lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z)
        let s = pow3(lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z)
        let r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        return TileColor.clamp(SIMD3(encoded(max(r, 0)), encoded(max(g, 0)), encoded(max(b, 0))))
    }

    static func pow3(_ v: Float) -> Float { v * v * v }
}

nonisolated func atan2Degrees(_ y: Float, _ x: Float) -> Float { atan2(y, x) * 180 / .pi }
