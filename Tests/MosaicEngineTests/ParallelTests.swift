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
        // The sliding maximum, split by rows and by strips of columns.
        let m = E.Morph.maxFilter(p, before: 4, after: 4)
        var wrong = 0
        for y in 0..<h {
            for x in 0..<w {
                var best = -Float.infinity
                for yy in max(y - 4, 0)...min(y + 4, h - 1) {
                    for xx in max(x - 4, 0)...min(x + 4, w - 1) { best = max(best, p[xx, yy]) }
                }
                if m[x, y] != best { wrong += 1 }
            }
        }
        #expect(wrong == 0)
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
    }

    @Test func partsCoverEveryIndexOnce() {
        for n in [0, 1, 5, 63, 64, 65, 1000, 100_003] {
            for grain in [1, 7, 4096] {
                let hits = E.Parallel.map(n, grain: grain, zero: 0) { $0 + 1 }
                #expect(hits == (0..<n).map { $0 + 1 }, "n \(n), grain \(grain)")
            }
        }
    }
}
