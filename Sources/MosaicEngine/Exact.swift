nonisolated extension MosaicEngine {
    /// The few transcendental functions the engine needs, in plain arithmetic: IEEE addition,
    /// multiplication, division and square root round the same everywhere, while each platform's
    /// libm may differ in the last bit. So the same photo makes the same mosaic on Linux and on a
    /// phone. Accurate to about 1e-15 relative (Double) over the ranges used here.
    nonisolated enum Exact {
        static let ln2Hi = 6.93147180369123816490e-01, ln2Lo = 1.90821492927058770002e-10

        /// eˣ: x = k·ln 2 + r with |r| ≤ ln 2 / 2, eʳ by its series, then scaled by 2ᵏ exactly.
        static func exp(_ x: Double) -> Double {
            guard x.isFinite else { return x.isNaN ? x : (x > 0 ? .infinity : 0) }
            if x < -745 { return 0 }
            if x > 709 { return .infinity }
            let k = (x / ln2Hi).rounded()
            let r = (x - k * ln2Hi) - k * ln2Lo
            var term = 1.0, sum = 1.0
            for n in 1...17 {
                term *= r / Double(n)
                sum += term
            }
            return scale(sum, Int(k))
        }

        /// x·2ᵏ, exactly (in two steps where 2ᵏ alone would leave the range).
        static func scale(_ x: Double, _ k: Int) -> Double {
            var x = x, k = k
            while k > 1000 { x *= Double(sign: .plus, exponent: 1000, significand: 1); k -= 1000 }
            while k < -1000 { x *= Double(sign: .plus, exponent: -1000, significand: 1); k += 1000 }
            return x * Double(sign: .plus, exponent: k, significand: 1)
        }

        /// ln x (x > 0): x = m·2ᵉ with m in [√½, √2), ln m = 2·atanh((m − 1)/(m + 1)) by its series.
        static func log(_ x: Double) -> Double {
            guard x > 0 else { return x == 0 ? -.infinity : .nan }
            guard x.isFinite else { return x }
            var e = Int(x.exponent)
            var m = x.significand   // [1, 2)
            if m > 1.4142135623730951 { m /= 2; e += 1 }
            let s = (m - 1) / (m + 1), s2 = s * s
            var term = s, sum = 0.0
            var n = 1.0
            while n < 60 {
                sum += term / n
                term *= s2
                n += 2
            }
            return 2 * sum + Double(e) * ln2Lo + Double(e) * ln2Hi
        }

        static func pow(_ x: Double, _ y: Double) -> Double {
            if x == 0 { return y > 0 ? 0 : (y == 0 ? 1 : .infinity) }
            return exp(y * log(x))
        }

        /// ∛x by Newton's method from an estimate halfway there.
        static func cbrt(_ x: Double) -> Double {
            if x == 0 || !x.isFinite { return x }
            let a = abs(x)
            var y = scale(1, Int(a.exponent) / 3)
            for _ in 0..<60 {
                let next = y - (y * y * y - a) / (3 * y * y)
                if next == y { break }
                y = next
            }
            // A last step from either side settles the rounding.
            y = y - (y * y * y - a) / (3 * y * y)
            return x < 0 ? -y : y
        }

        /// ∛x in Float for whole images: a bit-level first guess and two Newton steps.
        @inline(__always) static func cbrt(_ x: Float) -> Float {
            guard x > 0 else { return 0 }
            var y = Float(bitPattern: x.bitPattern / 3 &+ 709_921_077)
            y = (2 * y + x / (y * y)) / 3
            y = (2 * y + x / (y * y)) / 3
            y = (2 * y + x / (y * y)) / 3
            return y
        }

        /// sin and cos: reduced to a quarter turn about a multiple of π/2, then their series.
        static func sinCos(_ x: Double) -> (sin: Double, cos: Double) {
            let halfPi = 1.57079632679489661923
            let q = (x / halfPi).rounded()
            let r = (x - q * 1.57079632673412561417) - q * 6.07710050650619224932e-11
            let r2 = r * r
            var s = r, c = 1.0, ts = r, tc = 1.0
            for n in stride(from: 2, through: 30, by: 2) {
                tc *= -r2 / Double((n - 1) * n); c += tc
                ts *= -r2 / Double(n * (n + 1)); s += ts
            }
            switch ((Int(q) % 4) + 4) % 4 {
            case 0: return (s, c)
            case 1: return (c, -s)
            case 2: return (-s, -c)
            default: return (-c, s)
            }
        }
    }

    /// OKLab (Björn Ottosson, 2020) from and to gamma-encoded sRGB, in exact arithmetic: the tiles'
    /// and paints' colours.
    nonisolated enum Colour {
        static func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : Exact.pow((c + 0.055) / 1.055, 2.4) }
        static func encoded(_ c: Double) -> Double { c <= 0.0031308 ? 12.92 * c : 1.055 * Exact.pow(c, 1 / 2.4) - 0.055 }

        static func lab(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
            let r = linear(Double(rgb.x)), g = linear(Double(rgb.y)), b = linear(Double(rgb.z))
            let l = Exact.cbrt(Swift.max(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b, 0))
            let m = Exact.cbrt(Swift.max(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b, 0))
            let s = Exact.cbrt(Swift.max(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b, 0))
            return SIMD3(Float(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s),
                         Float(1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s),
                         Float(0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s))
        }

        /// Back to sRGB, the linear values clipped to 0...1 first, as the prototype's `srgb` does.
        static func rgb(_ lab: SIMD3<Float>) -> SIMD3<Float> {
            let L = Double(lab.x), a = Double(lab.y), b = Double(lab.z)
            func cube(_ v: Double) -> Double { v * v * v }
            let l = cube(L + 0.3963377774 * a + 0.2158037573 * b)
            let m = cube(L - 0.1055613458 * a - 0.0638541728 * b)
            let s = cube(L - 0.0894841775 * a - 1.2914855480 * b)
            func out(_ v: Double) -> Float { Float(encoded(Swift.min(Swift.max(v, 0), 1))) }
            return SIMD3(out(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                         out(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                         out(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s))
        }
    }
}
