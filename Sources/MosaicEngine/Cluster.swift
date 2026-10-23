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

        /// Each point's nearest centre, found many at once; their distances summed in order after.
        static func assign(_ data: [SIMD3<Float>], _ centers: [SIMD3<Float>], _ labels: inout [Int]) -> Double {
            var near = [Float](repeating: 0, count: data.count)
            data.withUnsafeBufferPointer { ds in
                centers.withUnsafeBufferPointer { cs in
                    labels.withUnsafeMutableBufferPointer { ls in
                        near.withUnsafeMutableBufferPointer { ns in
                            let ds = Parallel.Unchecked(ds), cs = Parallel.Unchecked(cs)
                            let ls = Parallel.Unchecked(ls), ns = Parallel.Unchecked(ns)
                            Parallel.ranges(ds.value.count, grain: 2048) { r in
                                for i in r {
                                    let v = ds.value[i]
                                    var best = 0, bd = Float.infinity
                                    for j in 0..<cs.value.count {
                                        let d = distance2(v, cs.value[j])
                                        if d < bd { bd = d; best = j }
                                    }
                                    ls.value[i] = best; ns.value[i] = bd
                                }
                            }
                        }
                    }
                }
            }
            var total = 0.0
            for d in near { total += Double(d) }
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
        /// `np.percentile(values, q)` with linear interpolation. Reorders `values`: the two ranks it
        /// interpolates are selected, not sorted for, and are the very values a sort puts there.
        static func percentile(_ values: inout [Float], _ q: Double) -> Float {
            guard !values.isEmpty else { return 0 }
            let n = values.count
            let pos = q / 100 * Double(n - 1)
            let lo = Int(pos), hi = Swift.min(lo + 1, n - 1)
            let t = Float(pos - Double(lo))
            return values.withUnsafeMutableBufferPointer { b in
                let a = select(b, lo)
                var c = a
                if hi > lo {
                    // Everything after rank lo is at least its value; the next rank is their least.
                    c = b[hi]
                    for i in (hi + 1)..<n where b[i] < c { c = b[i] }
                }
                return a + (c - a) * t
            }
        }

        /// The value of rank `k` (what `b.sorted()[k]` holds), leaving it at `k` with everything
        /// before it no greater and everything after it no less: quickselect, partitioning three
        /// ways about a median of three, so runs of equal values end it at once.
        static func select(_ b: UnsafeMutableBufferPointer<Float>, _ k: Int) -> Float {
            var l = 0, r = b.count
            while r - l > 16 {
                let x = b[l], y = b[(l + r) / 2], z = b[r - 1]
                let p = x < y ? (y < z ? y : (x < z ? z : x)) : (x < z ? x : (y < z ? z : y))
                var lt = l, i = l, gt = r
                while i < gt {
                    let v = b[i]
                    if v < p {
                        b.swapAt(lt, i); lt += 1; i += 1
                    } else if v > p {
                        gt -= 1; b.swapAt(i, gt)
                    } else {
                        i += 1
                    }
                }
                if k < lt { r = lt } else if k >= gt { l = gt } else { return p }
            }
            // A short run: insertion sort.
            for i in (l + 1)..<Swift.max(r, l + 1) {
                let v = b[i]
                var j = i
                while j > l && b[j - 1] > v { b[j] = b[j - 1]; j -= 1 }
                b[j] = v
            }
            return b[k]
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

    /// Björn Ottosson's OKLab over whole images: tables for the sRGB curve both ways, so a few
    /// million pixels convert in a blink (to within a few thousandths).
    nonisolated struct FastOKLab: Sendable {
        private let toLinear: [Float], toEncoded: [Float]
        private static let steps = 4096

        init() {
            let n = Self.steps
            toLinear = (0...(n + 1)).map { Float(Colour.linear(Swift.min(Double($0) / Double(n), 1))) }
            toEncoded = (0...(n + 1)).map { Float(Colour.encoded(Swift.min(Double($0) / Double(n), 1))) }
        }

        @inline(__always) private static func lookup(_ table: [Float], _ c: Float) -> Float {
            let v = Swift.min(Swift.max(c, 0), 1) * Float(steps)
            let i = Int(v)
            let t = v - Float(i)
            return table.withUnsafeBufferPointer { $0[i] + ($0[i + 1] - $0[i]) * t }
        }

        @inline(__always) func lab(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
            let r = Self.lookup(toLinear, rgb.x), g = Self.lookup(toLinear, rgb.y), b = Self.lookup(toLinear, rgb.z)
            let l = Exact.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
            let m = Exact.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
            let s = Exact.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
            return SIMD3(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                         1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                         0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
        }

        /// Back to sRGB, the linear values clipped to 0...1.
        @inline(__always) func rgb(_ lab: SIMD3<Float>) -> SIMD3<Float> {
            let L = lab.x, a = lab.y, b = lab.z
            let l0 = L + 0.3963377774 * a + 0.2158037573 * b
            let m0 = L - 0.1055613458 * a - 0.0638541728 * b
            let s0 = L - 0.0894841775 * a - 1.2914855480 * b
            let l = l0 * l0 * l0, m = m0 * m0 * m0, s = s0 * s0 * s0
            return SIMD3(Self.lookup(toEncoded, 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                         Self.lookup(toEncoded, -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                         Self.lookup(toEncoded, -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s))
        }
    }
}
