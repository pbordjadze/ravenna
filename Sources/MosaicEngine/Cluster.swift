#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

nonisolated extension MosaicEngine {
    /// A small deterministic generator (Steele, Lea and Flood's SplitMix64): the same seed gives the
    /// same numbers on every machine.
    nonisolated struct SplitMix64: Sendable {
        var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        /// Uniform in [0, 1).
        mutating func unit() -> Double { Double(next() >> 11) * 0x1p-53 }

        /// Uniform in 0..<n (n > 0), without modulo bias worth speaking of for the sizes used here.
        mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }

        /// `count` distinct indices from 0..<n in the order drawn (Floyd's algorithm), or all of them.
        mutating func sample(_ n: Int, count: Int) -> [Int] {
            guard count < n else { return Array(0..<n) }
            var taken = [Bool](repeating: false, count: n)
            var out: [Int] = []
            out.reserveCapacity(count)
            for j in (n - count)..<n {
                let t = below(j + 1)
                let pick = taken[t] ? j : t
                taken[pick] = true
                out.append(pick)
            }
            return out
        }
    }

    /// k-means as `cv2.kmeans` runs it with `KMEANS_PP_CENTERS`: k-means++ seeding (the best of three
    /// candidates per centre), Lloyd's iterations until the centres move less than ε or the count runs
    /// out, an empty cluster refilled from the biggest one's farthest point, the most compact of
    /// several attempts kept.
    nonisolated enum KMeans {
        struct Result { var centers: [SIMD3<Float>]; var compactness: Double }

        static func run(_ data: [SIMD3<Float>], k: Int, maxIterations: Int, epsilon: Double, attempts: Int,
                        rng: inout SplitMix64) -> Result {
            let n = data.count
            let k = Swift.min(k, n)
            guard k > 0 else { return Result(centers: [], compactness: 0) }
            var best: Result?
            var labels = [Int](repeating: 0, count: n)
            for _ in 0..<Swift.max(attempts, 1) {
                var centers = seed(data, k: k, rng: &rng)
                var compactness = 0.0
                for iteration in 0..<Swift.max(maxIterations, 2) {
                    compactness = assign(data, centers, &labels)
                    var sums = [SIMD3<Double>](repeating: .zero, count: k), counts = [Int](repeating: 0, count: k)
                    for i in 0..<n {
                        let v = data[i]
                        sums[labels[i]] += SIMD3(Double(v.x), Double(v.y), Double(v.z)); counts[labels[i]] += 1
                    }
                    // An empty cluster takes the point of the biggest cluster farthest from its centre.
                    for j in 0..<k where counts[j] == 0 {
                        let big = counts.indices.max { counts[$0] < counts[$1] || (counts[$0] == counts[$1] && $0 > $1) }!
                        var far = -1, fd: Float = -1
                        for i in 0..<n where labels[i] == big {
                            let d = distance2(data[i], centers[big])
                            if d > fd { fd = d; far = i }
                        }
                        guard far >= 0 else { continue }
                        let v = data[far], dv = SIMD3(Double(v.x), Double(v.y), Double(v.z))
                        sums[big] -= dv; counts[big] -= 1
                        sums[j] = dv; counts[j] = 1; labels[far] = j
                    }
                    var shift = 0.0
                    for j in 0..<k where counts[j] > 0 {
                        let m = sums[j] / Double(counts[j])
                        let c = SIMD3(Float(m.x), Float(m.y), Float(m.z))
                        shift = Swift.max(shift, Double(distance2(c, centers[j])))
                        centers[j] = c
                    }
                    if iteration > 0 && shift <= epsilon * epsilon { break }
                }
                compactness = assign(data, centers, &labels)
                if best == nil || compactness < best!.compactness { best = Result(centers: centers, compactness: compactness) }
            }
            return best!
        }

        @inline(__always) static func distance2(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
            let d = a - b
            return (d * d).sum()
        }

        /// The nearest centre (the lowest index on a tie).
        @inline(__always) static func nearest(_ v: SIMD3<Float>, _ centers: [SIMD3<Float>]) -> Int {
            var best = 0, bd = Float.infinity
            for j in centers.indices {
                let d = distance2(v, centers[j])
                if d < bd { bd = d; best = j }
            }
            return best
        }

        static func assign(_ data: [SIMD3<Float>], _ centers: [SIMD3<Float>], _ labels: inout [Int]) -> Double {
            var total = 0.0
            centers.withUnsafeBufferPointer { cs in
                for i in data.indices {
                    let v = data[i]
                    var best = 0, bd = Float.infinity
                    for j in 0..<cs.count {
                        let d = distance2(v, cs[j])
                        if d < bd { bd = d; best = j }
                    }
                    labels[i] = best; total += Double(bd)
                }
            }
            return total
        }

        static func seed(_ data: [SIMD3<Float>], k: Int, rng: inout SplitMix64) -> [SIMD3<Float>] {
            let n = data.count
            var centers = [data[rng.below(n)]]
            var dist = data.map { Double(distance2($0, centers[0])) }
            var sum = dist.reduce(0, +)
            var trial = [Double](repeating: 0, count: n)
            var bestDist = trial
            while centers.count < k {
                var bestSum = Double.infinity, bestIndex = -1
                for _ in 0..<3 {
                    var p = rng.unit() * sum
                    var ci = n - 1
                    for i in 0..<(n - 1) { p -= dist[i]; if p <= 0 { ci = i; break } }
                    var s = 0.0
                    let c = data[ci]
                    for i in 0..<n { trial[i] = Swift.min(dist[i], Double(distance2(data[i], c))); s += trial[i] }
                    if s < bestSum { bestSum = s; bestIndex = ci; swap(&trial, &bestDist) }
                }
                centers.append(data[bestIndex])
                sum = bestSum
                swap(&dist, &bestDist)
            }
            return centers
        }
    }

    nonisolated enum Stats {
        /// `np.percentile(values, q)` with linear interpolation. Sorts `values`.
        static func percentile(_ values: inout [Float], _ q: Double) -> Float {
            guard !values.isEmpty else { return 0 }
            values.sort()
            let pos = q / 100 * Double(values.count - 1)
            let lo = Int(pos), hi = Swift.min(lo + 1, values.count - 1)
            let t = Float(pos - Double(lo))
            return values[lo] + (values[hi] - values[lo]) * t
        }

        /// Per-channel percentiles of colours, as `np.percentile(px, q, axis=0)`.
        static func percentile(_ colors: [SIMD3<Float>], _ q: Double) -> SIMD3<Float> {
            var out = SIMD3<Float>.zero
            var ch = [Float](repeating: 0, count: colors.count)
            for c in 0..<3 {
                for i in colors.indices { ch[i] = colors[i][c] }
                out[c] = percentile(&ch, q)
            }
            return out
        }

        static func median(_ colors: [SIMD3<Float>]) -> SIMD3<Float> { percentile(colors, 50) }
    }

    /// Björn Ottosson's OKLab over whole images: a table for the sRGB curve, so a few million pixels
    /// convert in a blink.
    nonisolated struct FastOKLab: Sendable {
        private let table: [Float]
        private let steps = 4096

        init() {
            table = (0...4097).map { i in
                let c = Float(i) / 4096
                return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
        }

        @inline(__always) func linear(_ c: Float) -> Float {
            let v = Swift.min(Swift.max(c, 0), 1) * Float(steps)
            let i = Int(v)
            let t = v - Float(i)
            return table[i] + (table[i + 1] - table[i]) * t
        }

        @inline(__always) func lab(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
            let r = linear(rgb.x), g = linear(rgb.y), b = linear(rgb.z)
            let l = cbrtf(Swift.max(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b, 0))
            let m = cbrtf(Swift.max(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b, 0))
            let s = cbrtf(Swift.max(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b, 0))
            return SIMD3(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                         1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                         0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
        }
    }
}
