import Testing
@testable import MosaicEngine

/// The engine's shortcuts give the very bits of the long way: percentiles by selection, the series
/// stopped once nothing can change them, and the image passes split over the cores (each image here
/// big enough to be split into parts).
@Suite("The engine at speed")
struct ParallelTests {
    typealias E = MosaicEngine

    @Test func percentilesSelectWhatTheSortPuts() {
        var rng = E.SplitMix64(seed: 11)
        for n in [1, 2, 3, 7, 16, 17, 18, 33, 100, 257, 5000] {
            for levels in [3, 40, 1_000_000] {
                // Few levels make long runs of ties, as an image's pixels do.
                let values = (0..<n).map { _ in Float(rng.below(levels)) / Float(levels) }
                for q in [0.0, 5, 35, 50, 60, 70, 90, 95, 100] {
                    let sorted = values.sorted()
                    let pos = q / 100 * Double(n - 1)
                    let lo = Int(pos), hi = min(lo + 1, n - 1), t = Float(pos - Double(lo))
                    let want = sorted[lo] + (sorted[hi] - sorted[lo]) * t
                    var v = values
                    #expect(E.Stats.percentile(&v, q).bitPattern == want.bitPattern, "n \(n), \(levels) levels, q \(q)")
                    #expect(v.sorted() == sorted, "the same values, reordered")
                }
            }
        }
    }

    @Test func theSeriesStopWhereNothingCanChange() {
        // The series as they were, every term added.
        func exp(_ x: Double) -> Double {
            let k = (x / E.Exact.ln2Hi).rounded()
            let r = (x - k * E.Exact.ln2Hi) - k * E.Exact.ln2Lo
            var term = 1.0, sum = 1.0
            for n in 1...17 { term *= r / Double(n); sum += term }
            return E.Exact.scale(sum, Int(k))
        }
        func log(_ x: Double) -> Double {
            var e = Int(x.exponent), m = x.significand
            if m > 1.4142135623730951 { m /= 2; e += 1 }
            let s = (m - 1) / (m + 1), s2 = s * s
            var term = s, sum = 0.0, n = 1.0
            while n < 60 { sum += term / n; term *= s2; n += 2 }
            return 2 * sum + Double(e) * E.Exact.ln2Lo + Double(e) * E.Exact.ln2Hi
        }
        var rng = E.SplitMix64(seed: 5)
        var xs: [Double] = [1, 0.5, 2, 0.7071067811865476, 1.4142135623730951, 1e-9, 0.04045, 0.0031308]
        for _ in 0..<20000 { xs.append(rng.unit()) }
        for _ in 0..<5000 { xs.append(rng.unit() * 40 - 20) }
        for x in xs {
            #expect(E.Exact.exp(x).bitPattern == exp(x).bitPattern, "exp \(x)")
            if x > 0 { #expect(E.Exact.log(x).bitPattern == log(x).bitPattern, "log \(x)") }
        }
    }

    @Test func passesInPartsMatchTheirDefinitions() {
        var rng = E.SplitMix64(seed: 13)
        let w = 700, h = 200
        let p = E.Plane(width: w, height: h, pixels: (0..<(w * h)).map { _ in Float(rng.unit()) })
        // The sliding maximum, split by rows and by strips of columns: even windows (an even pitch
        // makes one), one-sided ones, and images shorter than the window or narrower than a strip.
        var wrong = 0
        for (pw, ph, before, after) in [(w, h, 4, 4), (w, h, 4, 3), (w, h, 0, 5), (w, h, 5, 0), (w, 7, 10, 9), (100, h, 3, 4)] {
            let q = E.Plane(width: pw, height: ph, pixels: (0..<(pw * ph)).map { p.pixels[$0] })
            let m = E.Morph.maxFilter(q, before: before, after: after)
            for y in 0..<ph {
                for x in 0..<pw {
                    var best = -Float.infinity
                    for yy in max(y - before, 0)...min(y + after, ph - 1) {
                        for xx in max(x - before, 0)...min(x + after, pw - 1) { best = max(best, q[xx, yy]) }
                    }
                    if m[x, y] != best { wrong += 1 }
                }
            }
            #expect(wrong == 0, "\(pw)×\(ph), window −\(before)…+\(after)")
        }
        // The distance transform, its columns in strips and its rows in bands.
        var seed = [UInt8](repeating: 0, count: w * h)
        for _ in 0..<60 { seed[rng.below(w * h)] = 1 }
        let d = E.Distance.edt(seed: seed, width: w, height: h)
        let seeds = seed.indices.filter { seed[$0] != 0 }
        wrong = 0
        for y in 0..<h {
            for x in 0..<w {
                var best = Int.max
                for s in seeds {
                    let dx = s % w - x, dy = s / w - y
                    best = min(best, dx * dx + dy * dy)
                }
                if d[x, y] != Float(Double(best).squareRoot()) { wrong += 1 }
            }
        }
        #expect(wrong == 0)
        // Blurs and the median: the whole image as its rows or its columns one at a time.
        let k = E.Blur.kernel(sigma: 2)
        let rows = E.Blur.convolveRows(p.pixels, width: w, height: h, kernel: k)
        let boxed = E.Blur.boxRows(p.pixels, width: w, height: h, radius: 6)
        for y in stride(from: 0, to: h, by: 37) {
            let line = Array(p.pixels[(y * w)..<((y + 1) * w)])
            #expect(Array(rows[(y * w)..<((y + 1) * w)]) == E.Blur.convolveRows(line, width: w, height: 1, kernel: k))
            #expect(Array(boxed[(y * w)..<((y + 1) * w)]) == E.Blur.boxRows(line, width: w, height: 1, radius: 6))
        }
        let cols = E.Blur.convolveColumns(p.pixels, width: w, height: h, kernel: k)
        let boxedCols = E.Blur.boxColumns(p.pixels, width: w, height: h, radius: 6)
        for x in stride(from: 0, to: w, by: 53) {
            let column = (0..<h).map { p.pixels[$0 * w + x] }
            #expect((0..<h).map { cols[$0 * w + x] } == E.Blur.convolveColumns(column, width: 1, height: h, kernel: k))
            #expect((0..<h).map { boxedCols[$0 * w + x] } == E.Blur.boxColumns(column, width: 1, height: h, radius: 6))
        }
        let labels = (0..<(w * h)).map { _ in UInt8(rng.below(5)) }
        let median = E.Morph.median(labels, width: w, height: h, size: 9, levels: 5)
        wrong = 0
        for y in stride(from: 0, to: h, by: 3) {
            for x in 0..<w {
                var count = [Int](repeating: 0, count: 5)
                for dy in -4...4 { for dx in -4...4 { count[Int(labels[E.clampIndex(y + dy, h) * w + E.clampIndex(x + dx, w)])] += 1 } }
                var c = 0, v = 0
                while c + count[v] <= 40 { c += count[v]; v += 1 }
                if median[y * w + x] != UInt8(v) { wrong += 1 }
            }
        }
        #expect(wrong == 0)
        // The rest of the split passes, whole against their rows one at a time or by definition.
        // The 2× bicubic and the bilinear resize, against the same taps one pixel at a time.
        let up = E.Resize.upscale2x(p.pixels, width: w, height: h)
        let even = E.Resize.cubic(0.75), odd = E.Resize.cubic(0.25)
        func taps(_ i: Int, _ n: Int, _ at: (Int) -> Float) -> (Float, Float) {
            let a = at(E.clampIndex(i - 2, n)), b = at(E.clampIndex(i - 1, n)), c = at(i)
            let d = at(E.clampIndex(i + 1, n)), e = at(E.clampIndex(i + 2, n))
            return (even.x * a + even.y * b + even.z * c + even.w * d, odd.x * b + odd.y * c + odd.z * d + odd.w * e)
        }
        var mid = [Float](repeating: 0, count: 2 * w * h)
        for y in 0..<h { for i in 0..<w { (mid[y * 2 * w + 2 * i], mid[y * 2 * w + 2 * i + 1]) = taps(i, w) { p.pixels[y * w + $0] } } }
        wrong = 0
        for x in 0..<(2 * w) {
            for i in 0..<h {
                let (top, bottom) = taps(i, h) { mid[$0 * 2 * w + x] }
                if up[2 * i * 2 * w + x] != top || up[(2 * i + 1) * 2 * w + x] != bottom { wrong += 1 }
            }
        }
        #expect(wrong == 0, "the bicubic by its taps")
        let wide = E.Resize.bilinear(p.pixels, width: w, height: h, to: 3 * w, 2 * h)
        func linear(_ n: Int, _ N: Int, _ d: Int) -> (Int, Int, Float) {
            let f = (Double(d) + 0.5) * Double(n) / Double(N) - 0.5
            var s = Int(f.rounded(.down)), t = Float(f - Double(s))
            if s < 0 { s = 0; t = 0 }
            if s >= n - 1 { s = n - 1; t = 0 }
            return (s, min(s + 1, n - 1), t)
        }
        wrong = 0
        for y in 0..<(2 * h) {
            let (y0, y1, ty) = linear(h, 2 * h, y)
            for x in 0..<(3 * w) {
                let (x0, x1, tx) = linear(w, 3 * w, x)
                let top = p.pixels[y0 * w + x0] * (1 - tx) + p.pixels[y0 * w + x1] * tx
                let bottom = p.pixels[y1 * w + x0] * (1 - tx) + p.pixels[y1 * w + x1] * tx
                if wide[y * 3 * w + x] != top * (1 - ty) + bottom * ty { wrong += 1 }
            }
        }
        #expect(wrong == 0, "the bilinear by its taps")
        let mask = (0..<(w * h)).map { _ in UInt8(rng.unit() < 0.3 ? 1 : 0) }
        let closed = E.Morph.close(mask, width: w, height: h, radius: 2)
        wrong = 0
        let dilated = (0..<(w * h)).map { i -> UInt8 in
            let x = i % w, y = i / w
            for yy in max(y - 2, 0)...min(y + 2, h - 1) { for xx in max(x - 2, 0)...min(x + 2, w - 1) where mask[yy * w + xx] != 0 { return 1 } }
            return 0
        }
        for i in 0..<(w * h) {
            let x = i % w, y = i / w
            var v: UInt8 = 1
            for yy in max(y - 2, 0)...min(y + 2, h - 1) { for xx in max(x - 2, 0)...min(x + 2, w - 1) where dilated[yy * w + xx] == 0 { v = 0 } }
            if closed[i] != v { wrong += 1 }
        }
        #expect(wrong == 0, "closing by its definition")
        let edges = E.Morph.labelEdges(labels, width: w, height: h)
        wrong = 0
        for i in 0..<(w * h) {
            let x = i % w, y = i / w
            var e: UInt8 = 0
            for yy in max(y - 1, 0)...min(y + 1, h - 1) { for xx in max(x - 1, 0)...min(x + 1, w - 1) where labels[yy * w + xx] != labels[i] { e = 1 } }
            if edges[i] != e { wrong += 1 }
        }
        #expect(wrong == 0, "label edges by their definition")
        let points = (0..<20000).map { _ in SIMD3<Float>(Float(rng.unit()), Float(rng.unit()), Float(rng.unit())) }
        let centers = (0..<9).map { _ in SIMD3<Float>(Float(rng.unit()), Float(rng.unit()), Float(rng.unit())) }
        var got = [Int](repeating: 0, count: points.count)
        let total = E.KMeans.assign(points, centers, &got)
        var sum = 0.0
        for (i, v) in points.enumerated() {
            #expect(got[i] == E.KMeans.nearest(v, centers))
            sum += Double(E.KMeans.distance2(v, centers[got[i]]))
        }
        #expect(total.bitPattern == sum.bitPattern, "the distances summed in order")
    }

    /// Each index is handed to some part (a part's writes are its own by construction).
    @Test func partsCoverEveryIndex() {
        for n in [0, 1, 5, 63, 64, 65, 1000, 100_003] {
            for grain in [1, 7, 4096] {
                let hits = E.Parallel.map(n, grain: grain, zero: 0) { $0 + 1 }
                #expect(hits == (0..<n).map { $0 + 1 }, "n \(n), grain \(grain)")
            }
        }
    }
}
